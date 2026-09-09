package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

const jwksURL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"

var firebaseNS = uuid.NewSHA1(uuid.NameSpaceURL, []byte("https://cockpit.octopilot.ai/firebase"))

type Verifier struct {
	project string
	allowDev bool
	shared  *pgxpool.Pool
	mu      sync.Mutex
	keys    map[string]*rsa.PublicKey
	fetched time.Time
	http    *http.Client
}

func New(project string, allowDev bool, shared *pgxpool.Pool) *Verifier {
	return &Verifier{
		project:  project,
		allowDev: allowDev,
		shared:   shared,
		keys:     map[string]*rsa.PublicKey{},
		http:     &http.Client{Timeout: 10 * time.Second},
	}
}

func (v *Verifier) UserID(r *http.Request) (uuid.UUID, error) {
	if authz := r.Header.Get("Authorization"); strings.HasPrefix(strings.ToLower(authz), "bearer ") {
		token := strings.TrimSpace(authz[7:])
		uid, fuid, err := v.parseFirebase(token)
		if err == nil {
			if real, ok := v.lookupOctopilot(r.Context(), fuid); ok {
				return real, nil
			}
			return uid, nil
		}
		if v.project != "" {
			return uuid.Nil, err
		}
	}
	if v.allowDev || v.project == "" {
		if raw := r.Header.Get("X-User-Id"); raw != "" {
			id, err := uuid.Parse(raw)
			if err != nil {
				return uuid.Nil, err
			}
			return id, nil
		}
	}
	return uuid.Nil, errors.New("missing credentials")
}

func (v *Verifier) lookupOctopilot(ctx context.Context, firebaseUID string) (uuid.UUID, bool) {
	if v.shared == nil || firebaseUID == "" {
		return uuid.Nil, false
	}
	var id uuid.UUID
	err := v.shared.QueryRow(ctx, `SELECT id FROM users WHERE firebase_uid = $1`, firebaseUID).Scan(&id)
	if err != nil {
		return uuid.Nil, false
	}
	return id, true
}

func (v *Verifier) parseFirebase(token string) (uuid.UUID, string, error) {
	if v.project == "" {
		return uuid.Nil, "", errors.New("firebase off")
	}
	parsed, err := jwt.Parse(token, func(t *jwt.Token) (any, error) {
		kid, _ := t.Header["kid"].(string)
		return v.key(kid)
	}, jwt.WithAudience(v.project), jwt.WithIssuer("https://securetoken.google.com/"+v.project))
	if err != nil || !parsed.Valid {
		return uuid.Nil, "", errors.New("invalid token")
	}
	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		return uuid.Nil, "", errors.New("claims")
	}
	fuid, _ := claims["user_id"].(string)
	if fuid == "" {
		fuid, _ = claims["sub"].(string)
	}
	if fuid == "" {
		return uuid.Nil, "", errors.New("no uid")
	}
	return uuid.NewSHA1(firebaseNS, []byte(fuid)), fuid, nil
}

func (v *Verifier) key(kid string) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if time.Since(v.fetched) > time.Hour || v.keys[kid] == nil {
		if err := v.refresh(); err != nil {
			return nil, err
		}
	}
	k := v.keys[kid]
	if k == nil {
		return nil, errors.New("unknown kid")
	}
	return k, nil
}

func (v *Verifier) refresh() error {
	resp, err := v.http.Get(jwksURL)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var doc struct {
		Keys []struct {
			Kid string `json:"kid"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
		return err
	}
	next := map[string]*rsa.PublicKey{}
	for _, k := range doc.Keys {
		nb, err := base64.RawURLEncoding.DecodeString(k.N)
		if err != nil {
			continue
		}
		eb, err := base64.RawURLEncoding.DecodeString(k.E)
		if err != nil {
			continue
		}
		e := 0
		for _, b := range eb {
			e = e<<8 + int(b)
		}
		next[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(nb), E: e}
	}
	v.keys = next
	v.fetched = time.Now()
	return nil
}
