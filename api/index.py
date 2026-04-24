"""
WMIS - Warehouse Management Information System
Vercel Serverless Backend — Vercel Postgres/Neon via psycopg2.
"""

import os
import uuid
import psycopg2
from flask import Flask, request, jsonify, send_file

app = Flask(__name__)

def get_conn():
    # Priority 1: DATABASE_URL (Standard Vercel/Neon integration)
    url = os.environ.get("DATABASE_URL")
    if url:
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql://", 1)
        return psycopg2.connect(url)
    
    # Priority 2: POSTGRES_URL (Older Vercel Postgres format)
    url_legacy = os.environ.get("POSTGRES_URL")
    if url_legacy:
        return psycopg2.connect(url_legacy)

    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        database=os.environ.get("DB_NAME", "wmis_db"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", "password")
    )


def rows_to_dict(cursor):
    """Convert cursor results to a list of dicts using column names."""
    if cursor.description is None:
        return []
    cols = [col[0] for col in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


def gen_id(prefix):
    return f"{prefix}{uuid.uuid4().hex[:8].upper()}"


def is_oversell_error(e):
    return "50000" in str(e) or "Overselling" in str(e)


# ============================================================
# FRONTEND SERVING
# ============================================================
@app.route("/")
def index():
    # Serving index.html from the root directory relative to this script
    # In Vercel, the directory structure is preserved in the function environment
    try:
        return send_file("../index.html")
    except:
        # Fallback if the path is slightly different in the build environment
        return send_file("index.html")

# ============================================================
# API ENDPOINTS
# ============================================================

@app.route("/api/products", methods=["GET"])
def get_products():
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute("""
            SELECT ProductID, SKU_ID, Category, Size, Color,
                   Batch_ID, CAST(InventoryDate AS VARCHAR) as InventoryDate, 
                   CAST(ExpiryDate AS VARCHAR) as ExpiryDate
            FROM   PRODUCTS
            ORDER  BY ProductID
        """)
        rows = rows_to_dict(cur)
        cur.close(); conn.close()
        return jsonify(rows), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/inventory", methods=["GET"])
def get_inventory():
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute("""
            SELECT
                i.InventoryID,
                i.LocationID,
                wl.Zone,
                wl.Aisle,
                wl.Shelf,
                i.ProductID,
                p.SKU_ID,
                p.Category,
                p.Size,
                p.Color,
                p.Batch_ID,
                CAST(p.ExpiryDate AS VARCHAR) as ExpiryDate,
                i.StaffID,
                s.Name  AS StaffName,
                i.Quantity,
                i.Status
            FROM   INVENTORY i
            INNER JOIN PRODUCTS           p  ON p.ProductID  = i.ProductID
            INNER JOIN WAREHOUSE_LOCATION wl ON wl.LocationID = i.LocationID
            INNER JOIN STAFF              s  ON s.StaffID     = i.StaffID
            ORDER  BY i.InventoryID
        """)
        rows = rows_to_dict(cur)
        cur.close(); conn.close()
        return jsonify(rows), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/orders", methods=["GET"])
def get_orders():
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute("""
            SELECT
                o.OrderID,
                o.StaffID,
                s.Name           AS StaffName,
                CAST(o.OrderDate AS VARCHAR) as OrderDate,
                o.OrderStatus,
                od.OrderDetailID,
                od.ProductID,
                p.SKU_ID,
                od.QuantityOrdered,
                w.WaybillID,
                w.TrackingStatus,
                w.DeliveryZone,
                w.CourierInfo
            FROM   ORDERS o
            INNER JOIN STAFF        s  ON s.StaffID      = o.StaffID
            LEFT  JOIN ORDER_DETAILS od ON od.OrderID    = o.OrderID
            LEFT  JOIN PRODUCTS      p  ON p.ProductID   = od.ProductID
            LEFT  JOIN WAYBILL       w  ON w.OrderID     = o.OrderID
            ORDER  BY o.OrderDate DESC
        """)
        rows = rows_to_dict(cur)
        cur.close(); conn.close()
        return jsonify(rows), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/stats", methods=["GET"])
def get_stats():
    try:
        conn = get_conn()
        cur  = conn.cursor()

        cur.execute("""
            SELECT p.ProductID, p.SKU_ID, p.Category, p.Color,
                   SUM(i.Quantity) AS TotalQty, i.Status
            FROM   INVENTORY i
            INNER JOIN PRODUCTS p ON p.ProductID = i.ProductID
            GROUP  BY p.ProductID, p.SKU_ID, p.Category, p.Color, i.Status
            ORDER  BY p.ProductID
        """)
        by_product = rows_to_dict(cur)

        cur.execute("""
            SELECT Status, COUNT(*) AS Count, SUM(Quantity) AS TotalQty
            FROM   INVENTORY
            GROUP  BY Status
        """)
        by_status = rows_to_dict(cur)

        cur.execute("""
            SELECT p.Category, SUM(i.Quantity) AS TotalQty, COUNT(*) AS ItemCount
            FROM   INVENTORY i
            INNER JOIN PRODUCTS p ON p.ProductID = i.ProductID
            GROUP  BY p.Category
            ORDER  BY TotalQty DESC
        """)
        by_category = rows_to_dict(cur)

        cur.execute("""
            SELECT OrderStatus, COUNT(*) AS Count
            FROM   ORDERS
            GROUP  BY OrderStatus
        """)
        by_order_status = rows_to_dict(cur)

        cur.close(); conn.close()
        return jsonify({
            "by_product":      by_product,
            "by_status":       by_status,
            "by_category":     by_category,
            "by_order_status": by_order_status
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/inbound", methods=["POST"])
def inbound():
    try:
        data       = request.get_json()
        product_id = data.get("ProductID", "").strip()
        location_id= data.get("LocationID", "").strip()
        staff_id   = data.get("StaffID", "STF001").strip()
        quantity   = int(data.get("Quantity", 0))

        if not product_id or not location_id or quantity <= 0:
            return jsonify({"error": "ProductID, LocationID, and Quantity (>0) are required."}), 400

        conn = get_conn()
        cur  = conn.cursor()

        cur.execute(
            "SELECT InventoryID FROM INVENTORY WHERE ProductID = %s AND LocationID = %s",
            (product_id, location_id)
        )
        existing = cur.fetchone()

        if existing:
            inv_id = existing[0]
            cur.execute(
                "UPDATE INVENTORY SET Quantity = Quantity + %s WHERE InventoryID = %s",
                (quantity, inv_id)
            )
            msg = f"Restocked {quantity} units. InventoryID: {inv_id}"
        else:
            inv_id = gen_id("INV")
            cur.execute(
                """INSERT INTO INVENTORY (InventoryID, LocationID, ProductID, StaffID, Quantity, Status)
                   VALUES (%s, %s, %s, %s, %s, 'Available')""",
                (inv_id, location_id, product_id, staff_id, quantity)
            )
            msg = f"New stock received. InventoryID: {inv_id}"

        conn.commit()
        cur.close(); conn.close()
        return jsonify({"message": msg, "InventoryID": inv_id}), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/order", methods=["POST"])
def place_order():
    try:
        data            = request.get_json()
        product_id      = data.get("ProductID", "").strip()
        quantity_ordered= int(data.get("QuantityOrdered", 0))
        staff_id        = data.get("StaffID", "STF002").strip()

        if not product_id or quantity_ordered <= 0:
            return jsonify({"error": "ProductID and QuantityOrdered (>0) are required."}), 400

        order_id       = gen_id("ORD")
        order_detail_id= gen_id("OD")

        conn = get_conn()
        cur  = conn.cursor()

        cur.execute(
            "INSERT INTO ORDERS (OrderID, StaffID, OrderDate, OrderStatus) VALUES (%s, %s, NOW(), 'Pending')",
            (order_id, staff_id)
        )
        cur.execute(
            "INSERT INTO ORDER_DETAILS (OrderDetailID, OrderID, ProductID, QuantityOrdered) VALUES (%s, %s, %s, %s)",
            (order_detail_id, order_id, product_id, quantity_ordered)
        )
        conn.commit()
        cur.close(); conn.close()
        return jsonify({"message": f"Order placed. OrderID: {order_id}", "OrderID": order_id}), 201

    except Exception as e:
        if is_oversell_error(e):
            return jsonify({"error": "Overselling prevented. Not enough stock or item is locked!"}), 400
        return jsonify({"error": str(e)}), 500


@app.route("/api/return", methods=["POST"])
def return_item():
    try:
        data        = request.get_json()
        inventory_id= data.get("InventoryID", "").strip()
        new_status  = data.get("NewStatus", "").strip()

        if not inventory_id or not new_status:
            return jsonify({"error": "InventoryID and NewStatus are required."}), 400

        conn = get_conn()
        cur  = conn.cursor()
        cur.execute(
            "UPDATE INVENTORY SET Status = %s WHERE InventoryID = %s",
            (new_status, inventory_id)
        )

        if cur.rowcount == 0:
            cur.close(); conn.close()
            return jsonify({"error": f"InventoryID '{inventory_id}' not found."}), 404

        conn.commit()
        cur.close(); conn.close()
        return jsonify({"message": f"Status updated to '{new_status}' for {inventory_id}"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True)
