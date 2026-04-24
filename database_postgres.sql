-- A. TABLE DEFINITIONS

-- 1) STAFF
CREATE TABLE STAFF (
    StaffID VARCHAR(20) NOT NULL PRIMARY KEY,
    Name    VARCHAR(100) NOT NULL,
    Role    VARCHAR(30) NOT NULL CHECK (Role IN ('Warehouse Staff', 'Supervisor'))
);

-- 2) WAREHOUSE_LOCATION
CREATE TABLE WAREHOUSE_LOCATION (
    LocationID   VARCHAR(20) NOT NULL PRIMARY KEY,
    Zone         VARCHAR(10) NOT NULL,
    Aisle        VARCHAR(10) NOT NULL,
    Shelf        VARCHAR(10) NOT NULL,
    MaxCapacity  INT         NOT NULL,
    CategoryRule VARCHAR(100) NULL
);

-- 3) PRODUCTS
CREATE TABLE PRODUCTS (
    ProductID     VARCHAR(20)  NOT NULL PRIMARY KEY,
    SKU_ID        VARCHAR(50)  NOT NULL,
    Category      VARCHAR(50) NOT NULL,
    Size          VARCHAR(20)  NULL,
    Color         VARCHAR(30)  NULL,
    Batch_ID      VARCHAR(30)  NULL,
    InventoryDate DATE         NULL,
    ExpiryDate    DATE         NULL
);

-- 4) INVENTORY
CREATE TABLE INVENTORY (
    InventoryID VARCHAR(20) NOT NULL PRIMARY KEY,
    LocationID  VARCHAR(20) NOT NULL REFERENCES WAREHOUSE_LOCATION(LocationID),
    ProductID   VARCHAR(20) NOT NULL REFERENCES PRODUCTS(ProductID),
    StaffID     VARCHAR(20) NOT NULL REFERENCES STAFF(StaffID),
    Quantity    INT         NOT NULL DEFAULT 0,
    Status      VARCHAR(20) NOT NULL DEFAULT 'Available' CHECK (Status IN ('Available', 'Locked', 'Quarantined'))
);

-- 5) ORDERS
CREATE TABLE ORDERS (
    OrderID     VARCHAR(20) NOT NULL PRIMARY KEY,
    StaffID     VARCHAR(20) NOT NULL REFERENCES STAFF(StaffID),
    OrderDate   TIMESTAMP   NOT NULL DEFAULT NOW(),
    OrderStatus VARCHAR(30) NOT NULL DEFAULT 'Pending' CHECK (OrderStatus IN ('Pending', 'Processing', 'Shipped', 'Cancelled'))
);

-- 6) ORDER_DETAILS
CREATE TABLE ORDER_DETAILS (
    OrderDetailID   VARCHAR(20) NOT NULL PRIMARY KEY,
    OrderID         VARCHAR(20) NOT NULL REFERENCES ORDERS(OrderID),
    ProductID       VARCHAR(20) NOT NULL REFERENCES PRODUCTS(ProductID),
    QuantityOrdered INT         NOT NULL
);

-- 7) WAYBILL
CREATE TABLE WAYBILL (
    WaybillID      VARCHAR(20)  NOT NULL PRIMARY KEY,
    OrderID        VARCHAR(20)  NOT NULL REFERENCES ORDERS(OrderID),
    TrackingStatus VARCHAR(50)  NOT NULL DEFAULT 'In Transit' CHECK (TrackingStatus IN ('In Transit', 'Out for Delivery', 'Delivered', 'Failed Delivery')),
    DeliveryZone   VARCHAR(50) NULL,
    CourierInfo    VARCHAR(100) NULL
);


-- B. TRIGGER: Overselling Guard & FIFO Stock Deduction
-- In PostgreSQL, triggers call a function.

CREATE OR REPLACE FUNCTION fn_prevent_overselling_and_deduct()
RETURNS TRIGGER AS $$
DECLARE
    available_qty INT;
BEGIN
    -- 1. Check total available quantity for the product
    SELECT COALESCE(SUM(Quantity), 0) INTO available_qty
    FROM INVENTORY
    WHERE ProductID = NEW.ProductID AND Status = 'Available';

    IF available_qty < NEW.QuantityOrdered THEN
        RAISE EXCEPTION 'Overselling prevented. Not enough stock! (Available: %, Requested: %)', available_qty, NEW.QuantityOrdered
        USING ERRCODE = '50000';
    END IF;

    -- 2. Deduct inventory using FIFO logic (set-based via CTE)
    WITH InventoryToDeduct AS (
        SELECT 
            InventoryID,
            Quantity,
            SUM(Quantity) OVER (ORDER BY InventoryID) as RunningTotal
        FROM INVENTORY
        WHERE ProductID = NEW.ProductID AND Status = 'Available'
    ),
    Deductions AS (
        SELECT 
            InventoryID,
            CASE 
                WHEN RunningTotal - Quantity < NEW.QuantityOrdered THEN 
                    LEAST(Quantity, NEW.QuantityOrdered - (RunningTotal - Quantity))
                ELSE 0 
            END as DeductAmount
        FROM InventoryToDeduct
    )
    UPDATE INVENTORY i
    SET Quantity = i.Quantity - d.DeductAmount
    FROM Deductions d
    WHERE i.InventoryID = d.InventoryID AND d.DeductAmount > 0;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_PreventOverselling
AFTER INSERT ON ORDER_DETAILS
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_overselling_and_deduct();


-- C. MOCK DATA

INSERT INTO STAFF (StaffID, Name, Role) VALUES
('STF001', 'Alice Johnson', 'Supervisor'),
('STF002', 'Bob Williams',  'Warehouse Staff'),
('STF003', 'Charlie Brown', 'Warehouse Staff');

INSERT INTO WAREHOUSE_LOCATION (LocationID, Zone, Aisle, Shelf, MaxCapacity, CategoryRule) VALUES
('LOC001', 'A', 'A1', 'S1', 500, 'Electronics Only'),
('LOC002', 'A', 'A1', 'S2', 300, 'Clothing Only'),
('LOC003', 'B', 'B2', 'S1', 400, 'Mixed'),
('LOC004', 'B', 'B2', 'S2', 250, 'Furniture Only'),
('LOC005', 'C', 'C3', 'S1', 600, 'Toys Only');

INSERT INTO PRODUCTS (ProductID, SKU_ID, Category, Size, Color, Batch_ID, InventoryDate, ExpiryDate) VALUES
('PRD001', 'SKU-ELC-001', 'Electronics', 'Medium', 'Black',  'BAT2026A', '2026-01-10', NULL),
('PRD002', 'SKU-ELC-002', 'Electronics', 'Small',  'White',  'BAT2026A', '2026-01-10', NULL),
('PRD003', 'SKU-CLT-001', 'Clothing',    'Large',  'Blue',   'BAT2026B', '2026-02-01', NULL),
('PRD004', 'SKU-CLT-002', 'Clothing',    'Medium', 'Red',    'BAT2026B', '2026-02-01', NULL),
('PRD005', 'SKU-FNT-001', 'Furniture',   'Large',  'Brown',  'BAT2026C', '2026-03-05', NULL),
('PRD006', 'SKU-FNT-002', 'Furniture',   'XLarge', 'Grey',   'BAT2026C', '2026-03-05', NULL),
('PRD007', 'SKU-TOY-001', 'Toys',        'Small',  'Green',  'BAT2026D', '2026-03-20', '2028-03-20');

INSERT INTO INVENTORY (InventoryID, LocationID, ProductID, StaffID, Quantity, Status) VALUES
('INV001', 'LOC001', 'PRD001', 'STF002', 120, 'Available'),
('INV002', 'LOC001', 'PRD002', 'STF002',  80, 'Available'),
('INV003', 'LOC002', 'PRD003', 'STF003', 200, 'Available'),
('INV004', 'LOC003', 'PRD004', 'STF003',  50, 'Locked'),
('INV005', 'LOC003', 'PRD005', 'STF002',  30, 'Available'),
('INV006', 'LOC004', 'PRD006', 'STF003',  15, 'Quarantined'),
('INV007', 'LOC005', 'PRD007', 'STF002', 300, 'Available');

INSERT INTO ORDERS (OrderID, StaffID, OrderDate, OrderStatus) VALUES
('ORD001','STF001','2026-04-15 09:00:00','Pending'),
('ORD002','STF002','2026-04-15 14:30:00','Processing'),
('ORD003','STF003','2026-04-16 10:15:00','Shipped'),
('ORD004','STF001','2026-04-16 16:45:00','Cancelled'),
('ORD005','STF002','2026-04-17 08:20:00','Pending'),
('ORD006','STF003','2026-04-17 13:50:00','Processing'),
('ORD007','STF001','2026-04-18 11:10:00','Shipped');

INSERT INTO WAYBILL (WaybillID, OrderID, TrackingStatus, DeliveryZone, CourierInfo) VALUES
('WB001','ORD001','In Transit','Zone A','DHL #001'),
('WB002','ORD002','Out for Delivery','Zone B','FedEx #002'),
('WB003','ORD003','Delivered','Zone C','UPS #003'),
('WB004','ORD004','Failed Delivery','Zone A','GHN #004'),
('WB005','ORD005','In Transit','Zone D','J&T #005'),
('WB006','ORD006','Out for Delivery','Zone B','Viettel Post #006'),
('WB007','ORD007','Delivered','Zone C','DHL #007');

-- D. VIEW: Shopee Platform Stock Synchronization
CREATE VIEW vw_ShopeeSync_Inventory AS
    SELECT
        p.SKU_ID,
        p.Category,
        i.Quantity AS AvailableQuantity
    FROM  INVENTORY i
    INNER JOIN PRODUCTS p ON i.ProductID = p.ProductID
    WHERE i.Status   = 'Available'
      AND i.Quantity > 0;
