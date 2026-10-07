//! Uploaded files in MinIO (S3, path style). Keys as the Python service:
//! `{user_id}/{document_id}/{filename}`.

use s3::creds::Credentials;
use s3::{Bucket, Region};

use crate::config::Config;

#[derive(Clone)]
pub struct Store {
    bucket: Box<Bucket>,
}

pub fn key_for(user: uuid::Uuid, document: uuid::Uuid, filename: &str) -> String {
    format!("{user}/{document}/{filename}")
}

impl Store {
    pub fn new(c: &Config) -> Result<Self, String> {
        let region = Region::Custom {
            region: c.object_store_region.clone(),
            endpoint: c.object_store_endpoint.clone(),
        };
        let creds = Credentials::new(
            Some(&c.object_store_access_key),
            Some(&c.object_store_secret_key),
            None,
            None,
            None,
        )
        .map_err(|e| e.to_string())?;
        let bucket = Bucket::new(&c.object_store_bucket, region, creds)
            .map_err(|e| e.to_string())?
            .with_path_style();
        Ok(Self { bucket })
    }

    pub async fn put(&self, key: &str, bytes: &[u8], content_type: &str) -> Result<(), String> {
        self.bucket
            .put_object_with_content_type(key, bytes, content_type)
            .await
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    pub async fn get(&self, key: &str) -> Result<Vec<u8>, String> {
        let r = self.bucket.get_object(key).await.map_err(|e| e.to_string())?;
        if r.status_code() >= 300 {
            return Err(format!("object store: HTTP {}", r.status_code()));
        }
        Ok(r.to_vec())
    }

    pub async fn delete(&self, key: &str) -> Result<(), String> {
        self.bucket.delete_object(key).await.map(|_| ()).map_err(|e| e.to_string())
    }
}
