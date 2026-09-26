//! Object storage for binaries (audio, materials, page renders, exports).
//!
//! Production: MinIO/S3 (`S3_*` env), clients download through presigned
//! URLs. Dev/tests: a local folder, served by `GET /v1/blobs/{key}` with an
//! HMAC-signed, expiring link — the same contract as a presigned URL.
//! Keys are always `{user_id}/{session_id}/…`, so a user's data is one prefix.

use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use hmac::{Hmac, Mac};
use s3::creds::Credentials;
use s3::{Bucket, Region};
use sha2::Sha256;

#[derive(Clone)]
pub enum Storage {
    Fs(FsStore),
    S3(Box<Bucket>),
}

#[derive(Clone)]
pub struct FsStore {
    root: PathBuf,
    public_base: String,
    signing_key: Vec<u8>,
}

pub struct S3Config {
    pub endpoint: String,
    pub bucket: String,
    pub access_key: String,
    pub secret_key: String,
    pub region: String,
}

impl Storage {
    pub fn fs(
        root: impl Into<PathBuf>,
        public_base: impl Into<String>,
        signing_key: Vec<u8>,
    ) -> Self {
        Storage::Fs(FsStore {
            root: root.into(),
            public_base: public_base.into(),
            signing_key,
        })
    }

    pub async fn s3(c: S3Config) -> Result<Self, String> {
        let region = Region::Custom {
            region: c.region,
            endpoint: c.endpoint,
        };
        let creds = Credentials::new(Some(&c.access_key), Some(&c.secret_key), None, None, None)
            .map_err(|e| e.to_string())?;
        let bucket = Bucket::new(&c.bucket, region.clone(), creds.clone())
            .map_err(|e| e.to_string())?
            .with_path_style();
        // Create the bucket on first run (MinIO); "already exists" is fine.
        if !bucket.exists().await.unwrap_or(false) {
            let _ = Bucket::create_with_path_style(
                &c.bucket,
                region,
                creds,
                s3::BucketConfiguration::default(),
            )
            .await;
        }
        Ok(Storage::S3(bucket))
    }

    pub async fn put(&self, key: &str, bytes: &[u8], content_type: &str) -> Result<(), String> {
        check_key(key)?;
        match self {
            Storage::Fs(fs) => {
                let path = fs.path(key)?;
                if let Some(dir) = path.parent() {
                    tokio::fs::create_dir_all(dir)
                        .await
                        .map_err(|e| e.to_string())?;
                }
                tokio::fs::write(path, bytes)
                    .await
                    .map_err(|e| e.to_string())
            }
            Storage::S3(b) => b
                .put_object_with_content_type(key, bytes, content_type)
                .await
                .map(|_| ())
                .map_err(|e| e.to_string()),
        }
    }

    pub async fn get(&self, key: &str) -> Result<Vec<u8>, String> {
        check_key(key)?;
        match self {
            Storage::Fs(fs) => tokio::fs::read(fs.path(key)?)
                .await
                .map_err(|e| e.to_string()),
            Storage::S3(b) => b
                .get_object(key)
                .await
                .map(|r| r.to_vec())
                .map_err(|e| e.to_string()),
        }
    }

    pub async fn exists(&self, key: &str) -> bool {
        match self {
            Storage::Fs(fs) => fs.path(key).map(|p| p.exists()).unwrap_or(false),
            Storage::S3(b) => b.head_object(key).await.is_ok(),
        }
    }

    pub async fn delete_prefix(&self, prefix: &str) -> Result<(), String> {
        check_key(prefix.trim_end_matches('/'))?;
        match self {
            Storage::Fs(fs) => {
                let path = fs.path(prefix.trim_end_matches('/'))?;
                match tokio::fs::remove_dir_all(&path).await {
                    Ok(()) => Ok(()),
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
                    Err(e) => Err(e.to_string()),
                }
            }
            Storage::S3(b) => {
                let pages = b
                    .list(prefix.to_string(), None)
                    .await
                    .map_err(|e| e.to_string())?;
                for page in pages {
                    for obj in page.contents {
                        b.delete_object(&obj.key).await.map_err(|e| e.to_string())?;
                    }
                }
                Ok(())
            }
        }
    }

    /// A time-limited download URL.
    pub async fn url(&self, key: &str, ttl_secs: u32) -> Result<String, String> {
        check_key(key)?;
        match self {
            Storage::Fs(fs) => {
                let exp = now() + ttl_secs as u64;
                let sig = fs.sign(key, exp);
                Ok(format!(
                    "{}/v1/blobs/{key}?exp={exp}&sig={sig}",
                    fs.public_base.trim_end_matches('/')
                ))
            }
            Storage::S3(b) => b
                .presign_get(key, ttl_secs, None)
                .await
                .map_err(|e| e.to_string()),
        }
    }

    /// A time-limited direct-upload URL (S3 only; the local store takes
    /// uploads through the API).
    pub async fn upload_url(&self, key: &str, ttl_secs: u32) -> Result<Option<String>, String> {
        check_key(key)?;
        match self {
            Storage::Fs(_) => Ok(None),
            Storage::S3(b) => b
                .presign_put(key, ttl_secs, None, None)
                .await
                .map(Some)
                .map_err(|e| e.to_string()),
        }
    }

    /// Verifies a local-store signed link; returns the file path to serve.
    pub fn verify_local(&self, key: &str, exp: u64, sig: &str) -> Option<PathBuf> {
        let Storage::Fs(fs) = self else { return None };
        if exp < now() || fs.sign(key, exp) != sig {
            return None;
        }
        fs.path(key).ok()
    }
}

impl FsStore {
    fn path(&self, key: &str) -> Result<PathBuf, String> {
        check_key(key)?;
        Ok(self.root.join(key))
    }

    fn sign(&self, key: &str, exp: u64) -> String {
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.signing_key).expect("hmac key");
        mac.update(format!("{key}\n{exp}").as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }
}

/// Keys are relative, `/`-separated, with no `..` — never a path escape.
fn check_key(key: &str) -> Result<(), String> {
    if key.is_empty() || key.len() > 1024 || key.starts_with('/') || key.contains('\\') {
        return Err("invalid storage key".into());
    }
    if Path::new(key)
        .components()
        .any(|c| !matches!(c, Component::Normal(_)))
    {
        return Err("invalid storage key".into());
    }
    Ok(())
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_path_escapes() {
        assert!(check_key("u/s/a.opus").is_ok());
        assert!(check_key("../etc/passwd").is_err());
        assert!(check_key("u/../../x").is_err());
        assert!(check_key("/abs").is_err());
        assert!(check_key("a\\b").is_err());
    }

    #[test]
    fn signed_links_expire_and_bind_the_key() {
        let st = Storage::fs("/tmp/x", "http://api", b"k".to_vec());
        let Storage::Fs(fs) = &st else { unreachable!() };
        let exp = now() + 60;
        let sig = fs.sign("u/s/a", exp);
        assert!(st.verify_local("u/s/a", exp, &sig).is_some());
        assert!(st.verify_local("u/s/b", exp, &sig).is_none());
        assert!(st
            .verify_local("u/s/a", now() - 1, &fs.sign("u/s/a", now() - 1))
            .is_none());
    }
}
