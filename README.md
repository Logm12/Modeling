# Warehouse Management Information System (WMIS)

A robust, cloud-native inventory and warehouse management system designed for real-time tracking, stock control, and logistics management. This application utilizes a Flask-based serverless architecture optimized for deployment on Vercel, with backend data persistence handled by Azure SQL Server.

## System Architecture

The application is structured to operate efficiently within a serverless environment:
- **Frontend**: A high-performance single-page application (SPA) built with standard web technologies, served directly as static content.
- **Backend**: A Python Flask application serving as a RESTful API, deployed as Vercel Serverless Functions.
- **Database**: Azure SQL Server integration using the `pymssql` driver for cross-platform compatibility and serverless-optimized connectivity.

## Features

- **Inventory Tracking**: Real-time monitoring of stock levels across different warehouse zones and locations.
- **Logistics Management**: Dedicated modules for inbound stock receiving, outbound order processing, and reverse logistics.
- **Status Control**: Granular control over inventory states including Available, Locked, and Quarantined.
- **Integrated Dashboard**: Visual analytics for warehouse performance, stock distribution, and order status summaries.
- **Concurrency Protection**: Database-level triggers prevent inventory overselling and ensure data integrity during simultaneous transactions.

## Technical Specifications

- **Backend Framework**: Flask 3.0.3
- **Database Driver**: pymssql (Serverless compatible)
- **Deployment Platform**: Vercel
- **UI Components**: Bootstrap 5, Chart.js

## Deployment Instructions

### Environment Variables

The application requires the following environment variables to be configured on the Vercel dashboard:

| Variable | Description |
| :--- | :--- |
| `DB_SERVER` | The hostname of your Azure SQL Server instance. |
| `DB_NAME` | The name of the target SQL database. |
| `DB_USER` | SQL Server authentication username. |
| `DB_PASSWORD` | SQL Server authentication password. |

### Database Setup

The database schema and initial mock data are provided in `database.sql`. Execute this script against your Azure SQL instance to initialize the system.

### Vercel Deployment

1. Install the Vercel CLI: `npm i -g vercel`
2. Authenticate and link your project.
3. Deploy to production: `vercel --prod`

Alternatively, connect your repository to Vercel for automated CI/CD deployments.

## API Documentation

The backend exposes several endpoints under the `/api` route prefix:

- `GET /api/inventory`: Retrieves full inventory details.
- `GET /api/products`: Lists all available products in the catalog.
- `GET /api/stats`: Provides aggregated data for dashboard visualization.
- `POST /api/inbound`: Processes incoming shipments.
- `POST /api/order`: Places new outbound orders.
- `POST /api/return`: Updates inventory status for reverse logistics.

## Security and Performance

- Configuration is handled exclusively via environment variables to prevent credential leakage.
- Frontend assets are served via Vercel's Edge Network for global low-latency performance.
- Direct database connections utilize server-side cursors to optimize memory usage.

## License
Proprietary. All rights reserved.
