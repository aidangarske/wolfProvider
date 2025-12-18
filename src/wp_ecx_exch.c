/* wp_ecx_exch.c
 *
 * Copyright (C) 2006-2025 wolfSSL Inc.
 *
 * This file is part of wolfProvider.
 *
 * wolfProvider is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * wolfProvider is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with wolfProvider. If not, see <http://www.gnu.org/licenses/>.
 */

#include <openssl/err.h>
#include <openssl/proverr.h>
#include <openssl/core_dispatch.h>
#include <openssl/core_names.h>
#include <openssl/params.h>
#include <openssl/ec.h>
#include <openssl/evp.h>
#include <stdio.h>

#include <wolfprovider/settings.h>
#include <wolfprovider/alg_funcs.h>

#if defined(WP_HAVE_X25519) || defined(WP_HAVE_X448)

/** Common key agree function pointer. */
typedef int (*WP_ECX_AGREE)(void* private_key, void* public_key, byte* out,
    word32* outlen);

/**
 * Alternative ECDH key exchange context.
 */
typedef struct wp_EcxCtx {
    /** Provider context - useful for getting library context. */
    WOLFPROV_CTX* provCtx;

    /** Reference to our key. */
    wp_Ecx* key;
    /** Reference to peer's public key. */
    wp_Ecx* peer;
} wp_EcxCtx;


/**
 * Create a new base alt ECDH key exchange context object.
 *
 * @param [in] provCtx  Provider context.
 * @return  ECDH key exchange object on success.
 * @return  NULL on failure.
 */
static wp_EcxCtx* wp_ecx_newctx(WOLFPROV_CTX* provCtx)
{
    wp_EcxCtx* ctx = NULL;

    if (wolfssl_prov_is_running()) {
        ctx = OPENSSL_zalloc(sizeof(*ctx));
    }
    if (ctx != NULL) {
        ctx->provCtx = provCtx;
    }

    return ctx;
}

/**
 * Free the alt ECDH key exchange context object.
 *
 * @param [in, out] ctx  Alt ECDH key exchange context object.
 */
static void wp_ecx_freectx(wp_EcxCtx* ctx)
{
    if (ctx != NULL) {
        /* UNCONDITIONAL DEBUG: Always print to stderr */
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_freectx: Freeing X25519/X448 key exchange context\n");
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_freectx: ctx=%p, key=%p, peer=%p\n", 
                ctx, ctx->key, ctx->peer);
        fflush(stderr);
        
        wp_ecx_free(ctx->peer);
        wp_ecx_free(ctx->key);
        OPENSSL_free(ctx);
        
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_freectx: Context freed\n");
        fflush(stderr);
    }
}

/**
 * Duplicate an alt ECDH key exchange context object.
 *
 * @param [in] src  Alt ECDH key exchange context object.
 * @return  Alt ECDH key exchange context object on success.
 * @return  NULL on failure.
 */
static wp_EcxCtx* wp_ecx_dupctx(wp_EcxCtx* src)
{
    wp_EcxCtx* dst = NULL;

    if (wolfssl_prov_is_running()) {
        dst = OPENSSL_zalloc(sizeof(*dst));
    }
    if (dst != NULL) {
        int ok = 1;

        dst->provCtx = src->provCtx;
        if ((src->key != NULL) && (!wp_ecx_up_ref(src->key))) {
            ok = 0;
        }
        else {
            dst->key = src->key;
        }
        if (ok && (src->peer != NULL) && (!wp_ecx_up_ref(src->peer))) {
            ok = 0;
        }
        else {
            dst->peer = src->peer;
        }
        if (!ok) {
            wp_ecx_free(src->key);
            OPENSSL_free(dst);
            dst = NULL;
        }
    }

    return dst;
}

/**
 * Initialize the alt ECDH key exchange object with private key and parameters.
 *
 * @param [in, out] ctx     Alt ECDH key exchange context object.
 * @param [in, out] ecx     Alt EC key object. (Up referenced.)
 * @param [in]      params  Parameters like KDF info.
 * @return  1 on success.
 * @return  0 on failure.
 */
static int wp_ecx_init(wp_EcxCtx* ctx, wp_Ecx* ecx, const OSSL_PARAM params[])
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X25519, "wp_ecx_init");
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: ctx=%p, ecx=%p\n", ctx, ecx);
    fflush(stderr);

    /* No settable parameters. */
    (void)params;

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Provider not running!\n");
        fflush(stderr);
        ok = 0;
    }
    if (ok && (ctx->key != ecx)) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Replacing old key %p with new key %p\n", ctx->key, ecx);
        fflush(stderr);
        wp_ecx_free(ctx->key);
        ctx->key = NULL;
        if (!wp_ecx_up_ref(ecx)) {
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: wp_ecx_up_ref failed!\n");
            fflush(stderr);
            ok = 0;
        }
    }
    if (ok) {
        ctx->key = ecx;
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Key set successfully\n");
        fflush(stderr);
    }

    WOLFPROV_LEAVE(WP_LOG_COMP_X25519, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

/**
 * Set the peer's public key into the alt ECDH key exchange context object.
 *
 * @param [in, out] ctx   Alt ECDH key exchange context object.
 * @param [in, out] peer  Peer's public key in alt ECDH key object.
 *                        (Up referenced.)
 * @return 1 on success.
 * @return 0 on failure.
 */
static int wp_ecx_set_peer(wp_EcxCtx* ctx, wp_Ecx* peer)
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X25519, "wp_ecx_set_peer");
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: ctx=%p, peer=%p\n", ctx, peer);
    fflush(stderr);

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Provider not running!\n");
        fflush(stderr);
        ok = 0;
    }

    if (ok && (ctx->peer != peer)) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Replacing old peer %p with new peer %p\n", ctx->peer, peer);
        fflush(stderr);
        wp_ecx_free(ctx->peer);
        ctx->peer = NULL;
        if (!wp_ecx_up_ref(peer)) {
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: wp_ecx_up_ref failed!\n");
            fflush(stderr);
            ok = 0;
        }
    }
    
    /* Fix for error -199 (ECC_BAD_ARG_E): Ensure peer public key MSB is cleared (RFC 7748) */
    /* This is done here (not in derive) because: */
    /* 1. Fix once when peer is set, not on every derive call */
    /* 2. wp_ecx_set_peer bypasses wp_x25519_import_public which normally clears MSB */
    /* 3. OpenSSL's default provider clears MSB during import, we must do the same */
    /* 4. We clear MSB directly and re-import using wc_curve25519_import_public_ex (same as wp_x25519_import_public) */
    /* NOTE: This fix ONLY applies to X25519 (32-byte keys), NOT X448 (56-byte keys) */
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Fixing peer key MSB, peer=%p\n", peer);
    fflush(stderr);
#ifdef WP_HAVE_X25519
    if (ok && peer != NULL) {
        void* peer_key = wp_ecx_get_key(peer);
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Checking peer key for MSB fix, peer_key=%p\n", peer_key);
        fflush(stderr);
        if (peer_key != NULL) {
            byte peer_pub[CURVE25519_KEYSIZE];
            word32 peer_pub_len = CURVE25519_KEYSIZE;
            int rc;
            
            /* Try to export as X25519 - if successful and size is 32, it's X25519 */
            /* If this fails or returns wrong size, it's X448 and we skip the MSB fix */
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Attempting to export peer key as X25519\n");
            fflush(stderr);
            rc = wc_curve25519_export_public_ex((curve25519_key*)peer_key, peer_pub, &peer_pub_len, EC25519_LITTLE_ENDIAN);
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Export result: rc=%d, peer_pub_len=%u (expected %d)\n", 
                    rc, peer_pub_len, CURVE25519_KEYSIZE);
            fflush(stderr);
            if (rc == 0 && peer_pub_len == CURVE25519_KEYSIZE) {
                /* This is X25519 - always normalize the key by re-importing */
                /* Even if exported bytes show MSB clear, the internal representation */
                /* might have MSB set, which causes wc_curve25519_shared_secret to fail */
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Confirmed X25519 key, normalizing MSB. Last byte=0x%02x\n", 
                        peer_pub[CURVE25519_KEYSIZE - 1]);
                fflush(stderr);
                /* Always clear MSB and re-import to ensure internal representation is correct */
                /* This matches wp_x25519_import_public behavior */
                peer_pub[CURVE25519_KEYSIZE - 1] &= 0x7f;
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: After MSB normalization, last byte=0x%02x\n", 
                        peer_pub[CURVE25519_KEYSIZE - 1]);
                fflush(stderr);
                /* Re-import using wc_curve25519_import_public_ex to normalize internal state */
                rc = wc_curve25519_import_public_ex(peer_pub, CURVE25519_KEYSIZE, (curve25519_key*)peer_key, EC25519_LITTLE_ENDIAN);
                if (rc != 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Failed to re-import X25519 peer key with normalized MSB, rc=%d\n", rc);
                    fflush(stderr);
                    ok = 0;
                } else {
                    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: X25519 peer key re-imported with normalized MSB successfully\n");
                    fflush(stderr);
                    /* Verify the re-import worked by exporting again */
                    word32 verify_len = CURVE25519_KEYSIZE;
                    byte verify_pub[CURVE25519_KEYSIZE];
                    rc = wc_curve25519_export_public_ex((curve25519_key*)peer_key, verify_pub, &verify_len, EC25519_LITTLE_ENDIAN);
                    if (rc == 0 && verify_len == CURVE25519_KEYSIZE) {
                        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Verification export - last byte=0x%02x (MSB=%d)\n",
                                verify_pub[CURVE25519_KEYSIZE - 1], (verify_pub[CURVE25519_KEYSIZE - 1] & 0x80) ? 1 : 0);
                        fflush(stderr);
                    }
                }
            } else {
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Not X25519 (export failed or wrong size), skipping MSB fix\n");
                fflush(stderr);
            }
            /* If export failed or size != 32, it's X448 or another type - skip MSB fix */
            /* X448 doesn't require MSB clearing per RFC 7748 */
        } else {
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: peer_key is NULL, skipping MSB fix\n");
            fflush(stderr);
        }
    }
#endif /* WP_HAVE_X25519 */
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: MSB fix complete, ok=%d\n", ok);
    fflush(stderr);
    
    if (ok) {
        ctx->peer = peer;
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Peer set successfully\n");
        fflush(stderr);
    }

    WOLFPROV_LEAVE(WP_LOG_COMP_X25519, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

#ifdef WP_HAVE_X25519

/*
 * X25519
 */

/** Order of Curve25519. Subtract from secret if larger. */
const unsigned char wp_curve25519_order[] = {
    0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xed
};

/**
 * Derive a secret/key using X25519.
 *
 * Can put the secret through a KDF.
 *
 * @param [in]  ctx      ECX key exchange context object.
 * @param [out] secret   Buffer to hold secret/key.
 * @param [out] secLen   Length of secret/key data in bytes.
 * @param [in]  secSize  Size of buffer in bytes.
 * @return 1 on success.
 * @return 0 on failure.
 */
static int wp_x25519_derive(wp_EcxCtx* ctx, unsigned char* secret,
    size_t* secLen, size_t secSize)
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X25519, "wp_x25519_derive");

    /* UNCONDITIONAL DEBUG: Always print to stderr regardless of debug build */
    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ENTER ctx=%p, secret=%p, secLen=%p, secSize=%zu\n",
            ctx, secret, secLen, secSize);
    fflush(stderr);
    
    if (ctx != NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key=%p, ctx->peer=%p\n",
                ctx->key, ctx->peer);
        fflush(stderr);
    }

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Provider not running!\n");
        fflush(stderr);
        ok = 0;
    }

    /* Validate context and keys before use */
    if (ok && ctx == NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx is NULL!\n");
        fflush(stderr);
        ok = 0;
    }
    if (ok && ctx->key == NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key is NULL!\n");
        fflush(stderr);
        ok = 0;
    }
    if (ok && ctx->peer == NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->peer is NULL!\n");
        fflush(stderr);
        ok = 0;
    }

    /* No output buffer, return secret size only. */
    if (ok && (secret == NULL)) {
        *secLen = CURVE25519_KEYSIZE;
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Returning secret size only: %d\n", CURVE25519_KEYSIZE);
        fflush(stderr);
    }
    else if (ok) {
        int rc;
        word32 len = (word32)secSize;
        int i;
        
        void* key_ptr = NULL;
        void* peer_ptr = NULL;
        
        /* Get key pointers with validation */
        if (ctx->key != NULL) {
            key_ptr = wp_ecx_get_key(ctx->key);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Got key_ptr=%p from ctx->key\n", key_ptr);
            fflush(stderr);
            if (key_ptr == NULL) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wp_ecx_get_key(ctx->key) returned NULL!\n");
                fflush(stderr);
                ok = 0;
            }
        } else {
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key is NULL before wp_ecx_get_key!\n");
            fflush(stderr);
            ok = 0;
        }
        
        if (ok && ctx->peer != NULL) {
            peer_ptr = wp_ecx_get_key(ctx->peer);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Got peer_ptr=%p from ctx->peer\n", peer_ptr);
            fflush(stderr);
            if (peer_ptr == NULL) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wp_ecx_get_key(ctx->peer) returned NULL!\n");
                fflush(stderr);
                ok = 0;
            }
        } else if (ok) {
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->peer is NULL before wp_ecx_get_key!\n");
            fflush(stderr);
            ok = 0;
        }

        if (ok) {
            /* Check and normalize BOTH keys before calling wc_curve25519_shared_secret */
            /* The error -199 can come from either the local key OR the peer key having MSB set */
            curve25519_key* local_key = (curve25519_key*)key_ptr;
            curve25519_key* peer_key = (curve25519_key*)peer_ptr;
            byte key_pub[CURVE25519_KEYSIZE];
            byte peer_pub_check[CURVE25519_KEYSIZE];
            word32 key_pub_len = CURVE25519_KEYSIZE;
            word32 peer_pub_check_len = CURVE25519_KEYSIZE;
            int need_fix_local = 0;
            int need_fix_peer = 0;
            
            /* Check local key */
            rc = wc_curve25519_export_public_ex(local_key, key_pub, &key_pub_len, EC25519_LITTLE_ENDIAN);
            if (rc == 0 && key_pub_len == CURVE25519_KEYSIZE) {
                if ((key_pub[CURVE25519_KEYSIZE - 1] & 0x80) != 0x00) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: LOCAL key has MSB set! Last byte=0x%02x\n", 
                            key_pub[CURVE25519_KEYSIZE - 1]);
                    fflush(stderr);
                    need_fix_local = 1;
                }
            }
            
            /* Check peer key */
            rc = wc_curve25519_export_public_ex(peer_key, peer_pub_check, &peer_pub_check_len, EC25519_LITTLE_ENDIAN);
            if (rc == 0 && peer_pub_check_len == CURVE25519_KEYSIZE) {
                if ((peer_pub_check[CURVE25519_KEYSIZE - 1] & 0x80) != 0x00) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: PEER key has MSB set! Last byte=0x%02x\n", 
                            peer_pub_check[CURVE25519_KEYSIZE - 1]);
                    fflush(stderr);
                    need_fix_peer = 1;
                }
            }
            
            /* Fix local key if needed */
            if (need_fix_local) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Normalizing LOCAL key MSB\n");
                fflush(stderr);
                key_pub[CURVE25519_KEYSIZE - 1] &= 0x7f;
                rc = wc_curve25519_import_public_ex(key_pub, CURVE25519_KEYSIZE, local_key, EC25519_LITTLE_ENDIAN);
                if (rc != 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Failed to normalize LOCAL key, rc=%d\n", rc);
                    fflush(stderr);
                    ok = 0;
                }
            }
            
            /* Fix peer key if needed */
            if (ok && need_fix_peer) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Normalizing PEER key MSB\n");
                fflush(stderr);
                peer_pub_check[CURVE25519_KEYSIZE - 1] &= 0x7f;
                rc = wc_curve25519_import_public_ex(peer_pub_check, CURVE25519_KEYSIZE, peer_key, EC25519_LITTLE_ENDIAN);
                if (rc != 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Failed to normalize PEER key, rc=%d\n", rc);
                    fflush(stderr);
                    ok = 0;
                }
            }
            
            if (ok) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Calling wc_curve25519_shared_secret with key_ptr=%p, peer_ptr=%p\n", 
                        key_ptr, peer_ptr);
                fflush(stderr);
                rc = wc_curve25519_shared_secret(local_key, peer_key, secret, &len);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wc_curve25519_shared_secret returned %d, len=%u\n", rc, len);
                fflush(stderr);
                
                if (rc != 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wc_curve25519_shared_secret FAILED with rc=%d\n", rc);
                    fflush(stderr);
                    ok = 0;
                }
            }
        }
        if (ok) {
            for (i = 0; i < CURVE25519_KEYSIZE; i++) {
                if (secret[i] != wp_curve25519_order[i]) {
                    break;
                }
            }
            if ((i < CURVE25519_KEYSIZE) &&
                (secret[i] > wp_curve25519_order[i])) {
                int16_t carry = 0;
                for (i = CURVE25519_KEYSIZE - 1; i >= 0; i--) {
                    carry += secret[i];
                    carry -= wp_curve25519_order[i];
                    secret[i] = (unsigned char)carry;
                    carry >>= 8;
                }
            }
        }
        if (ok) {
            *secLen = len;
            /* Switch endian. */
            for (i = 0; i < (int)len / 2; i++) {
                byte t = secret[i];
                secret[i] = secret[len - 1 - i];
                secret[len - 1 - i] = t;
            }
        }
    }

    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: EXIT returning %d\n", ok);
    fflush(stderr);
    WOLFPROV_LEAVE(WP_LOG_COMP_X25519, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

/** Dispatch table for X25519 key exchange. */
const OSSL_DISPATCH wp_x25519_keyexch_functions[] = {
    { OSSL_FUNC_KEYEXCH_NEWCTX,    (DFUNC)wp_ecx_newctx    },
    { OSSL_FUNC_KEYEXCH_FREECTX,   (DFUNC)wp_ecx_freectx   },
    { OSSL_FUNC_KEYEXCH_DUPCTX,    (DFUNC)wp_ecx_dupctx    },
    { OSSL_FUNC_KEYEXCH_INIT,      (DFUNC)wp_ecx_init      },
    { OSSL_FUNC_KEYEXCH_DERIVE,    (DFUNC)wp_x25519_derive },
    { OSSL_FUNC_KEYEXCH_SET_PEER,  (DFUNC)wp_ecx_set_peer  },
    { 0, NULL }
};

#endif /* WP_HAVE_X25519 */

#ifdef WP_HAVE_X448

/*
 * X448
 */

/**
 * Derive a secret/key using X448.
 *
 * Can put the secret through a KDF.
 *
 * @param [in]  ctx      ECX key exchange context object.
 * @param [out] secret   Buffer to hold secret/key.
 * @param [out] secLen   Length of secret/key data in bytes.
 * @param [in]  secSize  Size of buffer in bytes.
 * @return 1 on success.
 * @return 0 on failure.
 */
static int wp_x448_derive(wp_EcxCtx* ctx, unsigned char* secret,
    size_t* secLen, size_t secSize)
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X448, "wp_x448_derive");

    if (!wolfssl_prov_is_running()) {
        ok = 0;
    }

    /* No output buffer, return secret size only. */
    if (ok && (secret == NULL)) {
        *secLen = CURVE448_KEY_SIZE;
    }
    else if (ok) {
        int rc;
        word32 len = (word32)secSize;

        rc = wc_curve448_shared_secret(wp_ecx_get_key(ctx->key),
            wp_ecx_get_key(ctx->peer), secret, &len);
        if (rc != 0) {
            WOLFPROV_MSG_DEBUG_RETCODE(WP_LOG_LEVEL_DEBUG, "wc_curve448_shared_secret", rc);
            ok = 0;
        }
        if (ok) {
            word32 i;

            *secLen = len;
            /* Switch endian. */
            for (i = 0; i < len / 2; i++) {
                byte t = secret[i];
                secret[i] = secret[len - 1 - i];
                secret[len - 1 - i] = t;
            }
        }
    }

    WOLFPROV_LEAVE(WP_LOG_COMP_X448, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

/** Dispatch table for X448 key exchange. */
const OSSL_DISPATCH wp_x448_keyexch_functions[] = {
    { OSSL_FUNC_KEYEXCH_NEWCTX,    (DFUNC)wp_ecx_newctx   },
    { OSSL_FUNC_KEYEXCH_FREECTX,   (DFUNC)wp_ecx_freectx  },
    { OSSL_FUNC_KEYEXCH_DUPCTX,    (DFUNC)wp_ecx_dupctx   },
    { OSSL_FUNC_KEYEXCH_INIT,      (DFUNC)wp_ecx_init     },
    { OSSL_FUNC_KEYEXCH_DERIVE,    (DFUNC)wp_x448_derive  },
    { OSSL_FUNC_KEYEXCH_SET_PEER,  (DFUNC)wp_ecx_set_peer },
    { 0, NULL }
};

#endif /* WP_HAVE_X448 */

#endif /* WP_HAVE_X25519 || WP_HAVE_X448 */

