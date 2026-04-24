# Warehouse Management Information System (WMIS)

A robust, cloud-native warehouse management solution built for modern enterprises. This system utilizes a Flask backend deployed on Vercel's serverless infrastructure, with high-performance data persistence provided by Neon (Postgres).

## Architecture Overview

- **Frontend**: High-speed Single Page Application (SPA).
- **Backend API**: Python Flask serving RESTful endpoints.
- **Database**: Serverless PostgreSQL (Neon) with PgBouncer connection pooling.

## Technical Highlights

- **Serverless Optimized**: Designed specifically for Vercel's architecture, leveraging `psycopg2` for efficient database connectivity.
- **Data Integrity**: Uses database-level triggers to enforce FIFO (First-In-First-Out) inventory deduction and prevent overselling during concurrent transactions.
- **Automated Integration**: Fully compatible with Vercel's built-in Storage integration, minimizing manual configuration.

## Deployment Workflow

### 1. Database Provisioning
Connect your Vercel project to Neon via the **Storage** tab. This automatically configures the `DATABASE_URL` environment variable.

### 2. Schema Initialization
Execute the SQL commands found in `database_postgres.sql` through the Vercel Query Console to set up tables, functions, and triggers.

### 3. Application Launch
Redeploy your project on Vercel to allow the serverless functions to recognize the newly established database connection.

## API Documentation

- `GET /api/inventory`: Real-time stock status.
- `GET /api/stats`: Dashboard analytics and performance metrics.
- `POST /api/inbound`: Process incoming stock shipments.
- `POST /api/order`: Execute outbound orders with automated stock validation.
- `POST /api/return`: Update inventory status for reverse logistics.

## Environment Management
The system relies on the following integration-provided variables:
- `DATABASE_URL`: Production-grade pooled connection.
- `DATABASE_URL_UNPOOLED`: Direct database access.

## License
Proprietary. All rights reserved.
