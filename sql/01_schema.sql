-- =============================================================================
-- 01_schema.sql  |  Olist relational schema (PostgreSQL 13+)
-- Re-runnable: drops and recreates the `olist` schema.
-- Run:  psql -d olist -f sql/01_schema.sql
--
-- Design notes (see docs/decisions_log.md)
--  * Natural grain of each table is preserved; aggregation happens in views.
--  * order_reviews PK is order_id (review_id is reused across orders in the data).
--  * customers.customer_id is one-per-order; customer_unique_id is the person.
--  * No FK from customers/sellers to geolocation: 279 customer and 7 seller zip
--    prefixes have no coordinates. Zip is a soft (nullable-match) join.
-- =============================================================================
DROP SCHEMA IF EXISTS olist CASCADE;
CREATE SCHEMA olist;
SET search_path TO olist;

-- ---------------------------------------------------------------- dimensions
CREATE TABLE category_translation (
    product_category_name          TEXT PRIMARY KEY,
    product_category_name_english  TEXT NOT NULL
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix CHAR(5) PRIMARY KEY,
    geolocation_lat             DOUBLE PRECISION NOT NULL,
    geolocation_lng             DOUBLE PRECISION NOT NULL,
    n_raw_points                INTEGER NOT NULL,
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);

CREATE TABLE customers (
    customer_id              TEXT PRIMARY KEY,          -- one per ORDER
    customer_unique_id       TEXT NOT NULL,             -- the real person
    customer_zip_code_prefix CHAR(5) NOT NULL,
    customer_city            TEXT,
    customer_state           CHAR(2) NOT NULL
);

CREATE TABLE sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix CHAR(5) NOT NULL,
    seller_city            TEXT,
    seller_state           CHAR(2) NOT NULL
);

CREATE TABLE products (
    product_id                    TEXT PRIMARY KEY,
    product_category_name         TEXT NOT NULL REFERENCES category_translation,
    product_name_length           INTEGER,
    product_description_length    INTEGER,
    product_photos_qty            INTEGER,
    product_weight_g              NUMERIC(10,1),
    product_length_cm             NUMERIC(8,1),
    product_height_cm             NUMERIC(8,1),
    product_width_cm              NUMERIC(8,1),
    product_category_name_english TEXT,
    has_missing_dimensions        BOOLEAN NOT NULL
);

-- --------------------------------------------------------------------- facts
CREATE TABLE orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL REFERENCES customers,
    order_status                  TEXT NOT NULL
        CHECK (order_status IN ('created','approved','invoiced','processing',
                                'shipped','delivered','canceled','unavailable')),
    order_purchase_timestamp      TIMESTAMP NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL,
    -- flags and derived metrics created in Python (src/cleaning.py)
    has_items           BOOLEAN NOT NULL,
    is_valid_sale       BOOLEAN NOT NULL,   -- status NOT IN (canceled, unavailable)
    is_delivered        BOOLEAN NOT NULL,   -- delivered AND delivery date present
    in_analysis_window  BOOLEAN NOT NULL,   -- Jan 2017 .. Aug 2018
    ts_anomaly          BOOLEAN NOT NULL,
    delivery_days       DOUBLE PRECISION,   -- purchase -> delivered
    estimated_days      DOUBLE PRECISION,   -- purchase -> estimated date
    delay_days          DOUBLE PRECISION,   -- delivered - estimated (>0 = late)
    is_late             BOOLEAN,
    purchase_month      DATE NOT NULL
);

CREATE TABLE order_items (
    order_id            TEXT    NOT NULL REFERENCES orders,
    order_item_id       INTEGER NOT NULL,
    product_id          TEXT    NOT NULL REFERENCES products,
    seller_id           TEXT    NOT NULL REFERENCES sellers,
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2) NOT NULL CHECK (price > 0),
    freight_value       NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),
    item_total          NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id             TEXT    NOT NULL REFERENCES orders,
    payment_sequential   INTEGER NOT NULL,
    payment_type         TEXT    NOT NULL
        CHECK (payment_type IN ('credit_card','boleto','voucher','debit_card','not_defined')),
    payment_installments INTEGER NOT NULL,
    payment_value        NUMERIC(10,2) NOT NULL,
    is_zero_value        BOOLEAN NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE order_reviews (
    order_id                TEXT PRIMARY KEY REFERENCES orders,  -- 1 review per order
    review_id               TEXT NOT NULL,                       -- NOT unique
    review_score            SMALLINT NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    has_comment             BOOLEAN NOT NULL
);

-- ------------------------------------------------------------------- indexes
-- (PKs and FK targets are already indexed; these serve the analysis queries)
CREATE INDEX idx_orders_customer     ON orders (customer_id);
CREATE INDEX idx_orders_purchase_ts  ON orders (order_purchase_timestamp);
CREATE INDEX idx_orders_month        ON orders (purchase_month);
CREATE INDEX idx_orders_status       ON orders (order_status);
CREATE INDEX idx_customers_unique    ON customers (customer_unique_id);
CREATE INDEX idx_customers_state     ON customers (customer_state);
CREATE INDEX idx_items_product       ON order_items (product_id);
CREATE INDEX idx_items_seller        ON order_items (seller_id);
CREATE INDEX idx_products_category   ON products (product_category_name_english);
CREATE INDEX idx_reviews_score       ON order_reviews (review_score);
CREATE INDEX idx_payments_type       ON order_payments (payment_type);

COMMENT ON COLUMN customers.customer_id        IS 'Generated per order. NOT a person. Use customer_unique_id.';
COMMENT ON COLUMN order_reviews.review_id      IS 'Not unique in the source data; grain is one review per order.';
COMMENT ON COLUMN orders.is_valid_sale         IS 'FALSE for canceled/unavailable orders. Filter on this for revenue KPIs.';
COMMENT ON COLUMN orders.in_analysis_window    IS 'TRUE for purchases Jan 2017 - Aug 2018 (complete months).';
