# Sales Bill API

Node.js API for saving bills, loading previous bills, and sales ledger reports.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/login` | Login (`admin` / `admin` by default) |
| GET | `/api/bills/next-number?location=Location%201` | Next bill number |
| GET | `/api/bills/:billNo?location=Location%201` | Load bill by number |
| GET | `/api/bills/by-number/previous?billNo=5&location=Location%201` | Previous saved bill |
| POST | `/api/bills` | Save or update bill |
| GET | `/api/ledger?location=Location%201` | Sales ledger |

## Run locally

```bash
cd server
npm install
npm start
```

The API listens on port **3003** (same as the Flutter app's `api config.dart`).

## Deploy to your VPS

Copy the `server/` folder to your VPS and restart the Node process on port 3003.  
If you already have a login server running, merge the bill/ledger routes from `index.js` into your existing app.

Default login: **admin** / **admin**
