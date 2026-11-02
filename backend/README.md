# Waj-BE

The backend for **Wajbati**, built with FastAPI, SQLModel, and PostgreSQL. It provides APIs for users, cafeterias, menu items, orders, and ratings, with phone-number login, role-based access, and QR codes for order pickup.

## Requirements

- Python 3.11 or newer
- [uv](https://docs.astral.sh/uv/)
- A PostgreSQL database accessible from your machine

## Setup

1. Open the `Waj-BE` directory in a terminal.
2. Create the virtual environment and install dependencies:

   ```powershell
   uv sync
   ```

3. Copy the example environment file to `.env`:

   ```powershell
   Copy-Item .env.example .env
   ```

   Edit `.env` and set your actual database connection string and a long, random `JWT_SECRET`. Do not commit `.env` to Git because it contains secrets.

## Run the server

```powershell
uv run waj-be
```

After startup:

- Interactive API documentation: <http://127.0.0.1:8000/docs>
- OpenAPI JSON: <http://127.0.0.1:8000/openapi.json>

The application creates database tables at startup if they do not already exist.

## User roles

- `student`: places and tracks orders, and rates an order after pickup.
- `cafeteria_owner`: submits an application and must wait for admin approval before logging in or managing a cafeteria.
- `admin`: reviews pending cafeteria owner applications.

To create the first admin, register a regular account with the intended phone number, then run this command from the `Waj-BE` directory:

```powershell
uv run python scripts/promote_admin.py
```

Enter the account phone number in `+964` format and confirm by typing `yes`. Log in again afterward to receive an access token with the admin role.

## Main endpoints

- Authentication: `/auth/register`, `/auth/login`, `/auth/me`
- Cafeterias and menu items: `/cafeterias`
- Orders and order status: `/orders`
- Ratings: `/orders/{order_id}/rating` and `/cafeterias/{cafeteria_id}/ratings`
- Review cafeteria owner applications: `/admin/owner-applications/pending`
- Real-time order updates over WebSocket: `/ws/cafeterias/{cafeteria_id}/orders`

See [API.md](API.md) for request and response details, permissions, and examples.

## Notes

- Iraqi phone numbers are accepted in `07...` or `+9647...` format.
- Phone verification by SMS is not enabled yet.
- Payments, push notifications, and subscriptions require their respective services to be configured before they can be enabled.
