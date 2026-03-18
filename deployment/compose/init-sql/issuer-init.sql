--
-- Dataspace Issuer Service database initialisation
--
CREATE USER issuer WITH ENCRYPTED PASSWORD 'issuer' SUPERUSER;
CREATE DATABASE issuer;
\c issuer issuer

CREATE TABLE IF NOT EXISTS membership_attestations
(
    membership_type       integer   DEFAULT 0,
    holder_id             varchar                             NOT NULL,
    membership_start_date timestamp DEFAULT now()             NOT NULL,
    id                    varchar   DEFAULT gen_random_uuid() NOT NULL
        CONSTRAINT attestations_pk PRIMARY KEY
);

CREATE UNIQUE INDEX IF NOT EXISTS membership_attestation_holder_id_uindex
    ON membership_attestations (holder_id);

-- Seed consumer and provider so they can request credentials from the Issuer Service
INSERT INTO membership_attestations (membership_type, holder_id)
VALUES (1, 'did:web:consumer-identityhub%3A7083:consumer');
INSERT INTO membership_attestations (membership_type, holder_id)
VALUES (2, 'did:web:provider-identityhub%3A7083:provider');
