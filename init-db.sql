-- Create test database
CREATE DATABASE kite4rent_test;

-- Enable PostGIS extension on development database
\c kite4rent_dev;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Enable PostGIS extension on test database
\c kite4rent_test;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology; 