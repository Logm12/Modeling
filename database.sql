-- 0. CREATE DATABASE
CREATE DATABASE WMIS_DB;
GO

USE WMIS_DB;
GO


-- A. TABLE DEFINITIONS

-- 1) STAFF
CREATE TABLE STAFF (
    StaffID VARCHAR(20)   NOT NULL,
    Name    NVARCHAR(100) NOT NULL,
    Role    VARCHAR(30)   NOT NULL,
    CONSTRAINT PK_STAFF      PRIMARY KEY (StaffID),
    CONSTRAINT CK_STAFF_Role CHECK (Role IN ('Warehouse Staff', 'Supervisor'))
);
GO

-- 2) WAREHOUSE_LOCATION
--    ERD adds: CategoryRule
CREATE TABLE WAREHOUSE_LOCATION (
    LocationID   VARCHAR(20) NOT NULL,
    Zone         VARCHAR(10) NOT NULL,
    Aisle        VARCHAR(10) NOT NULL,
    Shelf        VARCHAR(10) NOT NULL,
    MaxCapacity  INT         NOT NULL,
    CategoryRule NVARCHAR(100) NULL,
    CONSTRAINT PK_WAREHOUSE_LOCATION PRIMARY KEY (LocationID)
);
GO

-- 3) PRODUCTS
CREATE TABLE PRODUCTS (
    ProductID     VARCHAR(20)  NOT NULL,
    SKU_ID        VARCHAR(50)  NOT NULL,
    Category      NVARCHAR(50) NOT NULL,
    Size          VARCHAR(20)  NULL,
    Color         VARCHAR(30)  NULL,
    Batch_ID      VARCHAR(30)  NULL,
    InventoryDate DATE         NULL,
    ExpiryDate    DATE         NULL,
    CONSTRAINT PK_PRODUCTS PRIMARY KEY (ProductID)
);
GO

-- 4) INVENTORY
CREATE TABLE INVENTORY (
    InventoryID VARCHAR(20) NOT NULL,
    LocationID  VARCHAR(20) NOT NULL,
    ProductID   VARCHAR(20) NOT NULL,
    StaffID     VARCHAR(20) NOT NULL,
    Quantity    INT         NOT NULL DEFAULT 0,
    Status      VARCHAR(20) NOT NULL DEFAULT 'Available',
    CONSTRAINT PK_INVENTORY          PRIMARY KEY (InventoryID),
    CONSTRAINT FK_INVENTORY_Location FOREIGN KEY (LocationID) REFERENCES WAREHOUSE_LOCATION(LocationID),
    CONSTRAINT FK_INVENTORY_Product  FOREIGN KEY (ProductID)  REFERENCES PRODUCTS(ProductID),
    CONSTRAINT FK_INVENTORY_Staff    FOREIGN KEY (StaffID)    REFERENCES STAFF(StaffID),
    CONSTRAINT CK_INVENTORY_Status   CHECK (Status IN ('Available', 'Locked', 'Quarantined'))
);
GO

-- 5) ORDERS
CREATE TABLE ORDERS (
    OrderID     VARCHAR(20) NOT NULL,
    StaffID     VARCHAR(20) NOT NULL,
    OrderDate   DATETIME    NOT NULL DEFAULT GETDATE(),
    OrderStatus VARCHAR(30) NOT NULL DEFAULT 'Pending',
    CONSTRAINT PK_ORDERS        PRIMARY KEY (OrderID),
    CONSTRAINT FK_ORDERS_Staff  FOREIGN KEY (StaffID) REFERENCES STAFF(StaffID),
    CONSTRAINT CK_ORDERS_Status CHECK (OrderStatus IN ('Pending', 'Processing', 'Shipped', 'Cancelled'))
);
GO

-- 6) ORDER_DETAILS
CREATE TABLE ORDER_DETAILS (
    OrderDetailID   VARCHAR(20) NOT NULL,
    OrderID         VARCHAR(20) NOT NULL,
    ProductID       VARCHAR(20) NOT NULL,
    QuantityOrdered INT         NOT NULL,
    CONSTRAINT PK_ORDER_DETAILS        PRIMARY KEY (OrderDetailID),
    CONSTRAINT FK_ORDERDETAILS_Order   FOREIGN KEY (OrderID)   REFERENCES ORDERS(OrderID),
    CONSTRAINT FK_ORDERDETAILS_Product FOREIGN KEY (ProductID) REFERENCES PRODUCTS(ProductID)
);
GO

-- 7) WAYBILL
CREATE TABLE WAYBILL (
    WaybillID      VARCHAR(20)  NOT NULL,
    OrderID        VARCHAR(20)  NOT NULL,
    TrackingStatus VARCHAR(50)  NOT NULL DEFAULT 'In Transit',
    DeliveryZone   NVARCHAR(50) NULL,
    CourierInfo    NVARCHAR(100) NULL,
    CONSTRAINT PK_WAYBILL             PRIMARY KEY (WaybillID),
    CONSTRAINT FK_WAYBILL_Order       FOREIGN KEY (OrderID) REFERENCES ORDERS(OrderID),
    CONSTRAINT CK_WAYBILL_TrackStatus CHECK (TrackingStatus IN ('In Transit', 'Out for Delivery', 'Delivered', 'Failed Delivery'))
);
GO


-- B. TRIGGER: Overselling Guard
CREATE TRIGGER trg_PreventOverselling
ON ORDER_DETAILS
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Check overselling (tổng tồn)
    IF EXISTS (
        SELECT 1
        FROM inserted i
        CROSS APPLY (
            SELECT SUM(Quantity) AS TotalQty
            FROM INVENTORY
            WHERE ProductID = i.ProductID
              AND Status = 'Available'
        ) inv
        WHERE inv.TotalQty < i.QuantityOrdered
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50000, 'Overselling prevented. Not enough stock!', 1;
        RETURN;
    END

    -- 2. Trừ tồn kho theo FIFO (set-based)
    ;WITH InventoryCTE AS (
        SELECT 
            inv.InventoryID,
            inv.ProductID,
            inv.Quantity,
            i.QuantityOrdered,
            SUM(inv.Quantity) OVER (
                PARTITION BY inv.ProductID
                ORDER BY inv.InventoryID
                ROWS UNBOUNDED PRECEDING
            ) AS RunningTotal
        FROM INVENTORY inv
        JOIN inserted i ON inv.ProductID = i.ProductID
        WHERE inv.Status = 'Available'
    ),
    DeductCTE AS (
        SELECT
            InventoryID,
            ProductID,
            Quantity,
            QuantityOrdered,
            RunningTotal,
            CASE 
                WHEN RunningTotal - Quantity < QuantityOrdered
                THEN 
                    CASE 
                        WHEN RunningTotal <= QuantityOrdered THEN Quantity
                        ELSE Quantity - (RunningTotal - QuantityOrdered)
                    END
                ELSE 0
            END AS DeductQty
        FROM InventoryCTE
    )
    UPDATE inv
    SET inv.Quantity = inv.Quantity - d.DeductQty
    FROM INVENTORY inv
    JOIN DeductCTE d ON inv.InventoryID = d.InventoryID
    WHERE d.DeductQty > 0;
END;
GO


-- 3. MOCK DATA

-- 1.STAFF
INSERT INTO STAFF (StaffID, Name, Role) VALUES
('STF001', 'Alice Johnson', 'Supervisor'),
('STF002', 'Bob Williams',  'Warehouse Staff'),
('STF003', 'Charlie Brown', 'Warehouse Staff');
GO

-- 2.WAREHOUSE_LOCATION
INSERT INTO WAREHOUSE_LOCATION (LocationID, Zone, Aisle, Shelf, MaxCapacity, CategoryRule) VALUES
('LOC001', 'A', 'A1', 'S1', 500, 'Electronics Only'),
('LOC002', 'A', 'A1', 'S2', 300, 'Clothing Only'),
('LOC003', 'B', 'B2', 'S1', 400, 'Mixed'),
('LOC004', 'B', 'B2', 'S2', 250, 'Furniture Only'),
('LOC005', 'C', 'C3', 'S1', 600, 'Toys Only');
GO

-- 3.PRODUCTS 
INSERT INTO PRODUCTS (ProductID, SKU_ID, Category, Size, Color, Batch_ID, InventoryDate, ExpiryDate) VALUES
('PRD001', 'SKU-ELC-001', 'Electronics', 'Medium', 'Black',  'BAT2026A', '2026-01-10', NULL),
('PRD002', 'SKU-ELC-002', 'Electronics', 'Small',  'White',  'BAT2026A', '2026-01-10', NULL),
('PRD003', 'SKU-CLT-001', 'Clothing',    'Large',  'Blue',   'BAT2026B', '2026-02-01', NULL),
('PRD004', 'SKU-CLT-002', 'Clothing',    'Medium', 'Red',    'BAT2026B', '2026-02-01', NULL),
('PRD005', 'SKU-FNT-001', 'Furniture',   'Large',  'Brown',  'BAT2026C', '2026-03-05', NULL),
('PRD006', 'SKU-FNT-002', 'Furniture',   'XLarge', 'Grey',   'BAT2026C', '2026-03-05', NULL),
('PRD007', 'SKU-TOY-001', 'Toys',        'Small',  'Green',  'BAT2026D', '2026-03-20', '2028-03-20');
GO

-- 4.INVENTORY 
INSERT INTO INVENTORY (InventoryID, LocationID, ProductID, StaffID, Quantity, Status) VALUES
('INV001', 'LOC001', 'PRD001', 'STF002', 120, 'Available'),
('INV002', 'LOC001', 'PRD002', 'STF002',  80, 'Available'),
('INV003', 'LOC002', 'PRD003', 'STF003', 200, 'Available'),
('INV004', 'LOC003', 'PRD004', 'STF003',  50, 'Locked'),
('INV005', 'LOC003', 'PRD005', 'STF002',  30, 'Available'),
('INV006', 'LOC004', 'PRD006', 'STF003',  15, 'Quarantined'),
('INV007', 'LOC005', 'PRD007', 'STF002', 300, 'Available');
GO

-- 5.ORDERS
INSERT INTO ORDERS (OrderID, StaffID, OrderDate, OrderStatus) VALUES
('ORD001','STF001','2026-04-15 09:00:00','Pending'),
('ORD002','STF002','2026-04-15 14:30:00','Processing'),
('ORD003','STF003','2026-04-16 10:15:00','Shipped'),
('ORD004','STF001','2026-04-16 16:45:00','Cancelled'),
('ORD005','STF002','2026-04-17 08:20:00','Pending'),
('ORD006','STF003','2026-04-17 13:50:00','Processing'),
('ORD007','STF001','2026-04-18 11:10:00','Shipped');
GO

-- 6.WAYBILL 
INSERT INTO WAYBILL (WaybillID, OrderID, TrackingStatus, DeliveryZone, CourierInfo) VALUES
('WB001','ORD001','In Transit','Zone A','DHL #001'),
('WB002','ORD002','Out for Delivery','Zone B','FedEx #002'),
('WB003','ORD003','Delivered','Zone C','UPS #003'),
('WB004','ORD004','Failed Delivery','Zone A','GHN #004'),
('WB005','ORD005','In Transit','Zone D','J&T #005'),
('WB006','ORD006','Out for Delivery','Zone B','Viettel Post #006'),
('WB007','ORD007','Delivered','Zone C','DHL #007');
GO


-- 4. VIEW: Shopee Platform Stock Synchronization
CREATE VIEW vw_ShopeeSync_Inventory AS
    SELECT
        p.SKU_ID,
        p.Category,
        i.Quantity AS AvailableQuantity
    FROM  INVENTORY i
    INNER JOIN PRODUCTS p ON i.ProductID = p.ProductID
    WHERE i.Status   = 'Available'
      AND i.Quantity > 0;
GO

PRINT '=== WMIS_DB Created Successfully ===';
GO
