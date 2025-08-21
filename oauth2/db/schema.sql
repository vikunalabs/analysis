-- Create schema if not exists
DROP SCHEMA IF EXISTS hmp CASCADE;
CREATE SCHEMA IF NOT EXISTS hmp;

SET search_path TO hmp;

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-----------------------------------------------------------
----------- SPRING MODULITH - EVENT PUBLICATION -----------
-----------------------------------------------------------
CREATE TABLE hmp.event_publication
(
    id               UUID                     NOT NULL,
    listener_id      TEXT                     NOT NULL,
    event_type       TEXT                     NOT NULL,
    serialized_event TEXT                     NOT NULL,
    publication_date TIMESTAMP WITH TIME ZONE NOT NULL,
    completion_date  TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id)
);

-----------------------------------------------------------
--------------------- OAUTH2 CLIENTS  ---------------------
-----------------------------------------------------------

CREATE TABLE IF NOT EXISTS hmp.oauth2_registered_client
(
    id                            VARCHAR(100) PRIMARY KEY,
    client_id                     VARCHAR(100) NOT NULL,
    client_id_issued_at           TIMESTAMP,
    client_secret                 VARCHAR(200),
    client_secret_expires_at      TIMESTAMP,
    client_name                   VARCHAR(200),
    client_authentication_methods TEXT         NOT NULL,
    authorization_grant_types     TEXT         NOT NULL,
    redirect_uris                 TEXT         NOT NULL,
    post_logout_redirect_uris     TEXT,
    front_channel_logout_uri      VARCHAR(1000),
    back_channel_logout_uri       VARCHAR(1000),
    scopes                        TEXT         NOT NULL,
    client_settings               TEXT         NOT NULL,
    token_settings                TEXT         NOT NULL
);

-----------------------------------------------------------
----------------- USER PROFILES & ACCOUNTS ----------------
-----------------------------------------------------------

CREATE TABLE hmp.user_profiles
(
    id           UUID PRIMARY KEY,
    first_name   VARCHAR(100),
    last_name    VARCHAR(100),
    organisation VARCHAR(100),
    consent      BOOLEAN     NOT NULL DEFAULT FALSE,
    notification BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version      INTEGER     NOT NULL DEFAULT 0
);

-- Create the table in hmp schema
CREATE TABLE hmp.user_accounts
(
    id                  UUID PRIMARY KEY,
    username            VARCHAR(50) UNIQUE  NOT NULL,
    password            VARCHAR(255), -- Store hashed passwords
    email               VARCHAR(255) UNIQUE NOT NULL,
    role                VARCHAR(20)         NOT NULL, -- Stores enum values ('user', 'manager', 'admin')
    account_enabled     BOOLEAN             NOT NULL DEFAULT false,
    credentials_expired BOOLEAN             NOT NULL DEFAULT false,
    account_expired     BOOLEAN             NOT NULL DEFAULT false,
    account_locked      BOOLEAN             NOT NULL DEFAULT false,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at   TIMESTAMPTZ,
    version             INTEGER             NOT NULL DEFAULT 0
);

ALTER TABLE hmp.user_accounts
    ADD CONSTRAINT fk_user_account_user_profile
        FOREIGN KEY (id)
            REFERENCES hmp.user_profiles (id)
            ON DELETE CASCADE;


-- Create indexes for better performance on login fields
CREATE INDEX idx_user_accounts_username ON hmp.user_accounts (username);
CREATE INDEX idx_user_accounts_email ON hmp.user_accounts (email);

-- Composite index if you frequently query by both username and email
CREATE INDEX idx_user_accounts_username_email ON hmp.user_accounts (username, email);