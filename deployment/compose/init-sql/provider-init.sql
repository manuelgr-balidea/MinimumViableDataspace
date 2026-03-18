--
-- Provider Corp database initialisation (catalog server, qna, manufacturing, identity hub)
--
CREATE USER catalog_server WITH ENCRYPTED PASSWORD 'catalog_server' SUPERUSER;
CREATE DATABASE catalog_server;
\c catalog_server

\c postgres postgres

CREATE USER qna WITH ENCRYPTED PASSWORD 'provider-qna' SUPERUSER;
CREATE DATABASE provider_qna;
\c provider_qna

\c postgres postgres

CREATE USER manufacturing WITH ENCRYPTED PASSWORD 'provider-manufacturing' SUPERUSER;
CREATE DATABASE provider_manufacturing;
\c provider_manufacturing

\c postgres postgres

CREATE USER identity WITH ENCRYPTED PASSWORD 'identity' SUPERUSER;
CREATE DATABASE identity;
\c identity identity
