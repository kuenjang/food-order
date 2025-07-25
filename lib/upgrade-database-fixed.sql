-- 修正的資料庫升級腳本
-- 處理 UUID 和 INTEGER 類型不匹配的問題

-- 1. 建立 order_channels 資料表（如果不存在）
CREATE TABLE IF NOT EXISTS order_channels (
    id SERIAL PRIMARY KEY,
    channel_code VARCHAR(10) UNIQUE NOT NULL,
    channel_name VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 2. 檢查並插入通道資料（如果不存在）
INSERT INTO order_channels (channel_code, channel_name) 
VALUES ('ON', '線上點餐')
ON CONFLICT (channel_code) DO NOTHING;

INSERT INTO order_channels (channel_code, channel_name) 
VALUES ('WA', '現場點餐')
ON CONFLICT (channel_code) DO NOTHING;

-- 3. 檢查 orders 資料表的主鍵類型
DO $$
DECLARE
    pk_type text;
BEGIN
    -- 檢查 orders 資料表的主鍵類型
    SELECT data_type INTO pk_type
    FROM information_schema.columns 
    WHERE table_name = 'orders' 
    AND column_name = 'id' 
    AND table_schema = 'public';
    
    -- 如果 orders 資料表不存在，建立新的（使用 UUID）
    IF pk_type IS NULL THEN
        CREATE TABLE orders (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            order_number VARCHAR(20) UNIQUE,
            channel_id INTEGER REFERENCES order_channels(id),
            customer_name VARCHAR(100),
            customer_phone VARCHAR(20),
            total_amount DECIMAL(10,2),
            status VARCHAR(20) DEFAULT 'pending',
            payment_method VARCHAR(20) DEFAULT 'cash',
            delivery_type VARCHAR(20) DEFAULT 'dine_in',
            special_notes TEXT,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        );
    END IF;
END $$;

-- 4. 為現有的 orders 資料表添加缺少的欄位（如果不存在）
DO $$
BEGIN
    -- 檢查並添加 order_number 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'order_number') THEN
        ALTER TABLE orders ADD COLUMN order_number VARCHAR(20);
    END IF;
    
    -- 檢查並添加 channel_id 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'channel_id') THEN
        ALTER TABLE orders ADD COLUMN channel_id INTEGER REFERENCES order_channels(id);
    END IF;
    
    -- 檢查並添加 customer_name 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'customer_name') THEN
        ALTER TABLE orders ADD COLUMN customer_name VARCHAR(100);
    END IF;
    
    -- 檢查並添加 customer_phone 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'customer_phone') THEN
        ALTER TABLE orders ADD COLUMN customer_phone VARCHAR(20);
    END IF;
    
    -- 檢查並添加 total_amount 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'total_amount') THEN
        ALTER TABLE orders ADD COLUMN total_amount DECIMAL(10,2);
    END IF;
    
    -- 檢查並添加 payment_method 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'payment_method') THEN
        ALTER TABLE orders ADD COLUMN payment_method VARCHAR(20) DEFAULT 'cash';
    END IF;
    
    -- 檢查並添加 delivery_type 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'delivery_type') THEN
        ALTER TABLE orders ADD COLUMN delivery_type VARCHAR(20) DEFAULT 'dine_in';
    END IF;
    
    -- 檢查並添加 special_notes 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'special_notes') THEN
        ALTER TABLE orders ADD COLUMN special_notes TEXT;
    END IF;
    
    -- 檢查並添加 updated_at 欄位
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'updated_at') THEN
        ALTER TABLE orders ADD COLUMN updated_at TIMESTAMP DEFAULT NOW();
    END IF;
END $$;

-- 5. 建立 order_items 資料表（如果不存在）- 使用 UUID 外鍵
CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    item_name VARCHAR(100) NOT NULL,
    item_price DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    special_notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 6. 建立 queue_numbers 資料表（如果不存在）- 使用 UUID 外鍵
CREATE TABLE IF NOT EXISTS queue_numbers (
    id SERIAL PRIMARY KEY,
    order_id UUID REFERENCES orders(id),
    queue_number VARCHAR(10) NOT NULL,
    status VARCHAR(20) DEFAULT 'waiting',
    called_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 7. 建立 daily_counters 資料表（如果不存在）
CREATE TABLE IF NOT EXISTS daily_counters (
    id SERIAL PRIMARY KEY,
    date DATE UNIQUE NOT NULL,
    channel_code VARCHAR(10) NOT NULL,
    counter INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 8. 建立索引（如果不存在）
DO $$
BEGIN
    -- orders 索引
    IF NOT EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_orders_order_number') THEN
        CREATE INDEX idx_orders_order_number ON orders(order_number);
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_orders_channel_id') THEN
        CREATE INDEX idx_orders_channel_id ON orders(channel_id);
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_orders_status') THEN
        CREATE INDEX idx_orders_status ON orders(status);
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_orders_created_at') THEN
        CREATE INDEX idx_orders_created_at ON orders(created_at);
    END IF;
    
    -- queue_numbers 索引
    IF NOT EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_queue_numbers_status') THEN
        CREATE INDEX idx_queue_numbers_status ON queue_numbers(status);
    END IF;
    
    -- daily_counters 索引
    IF NOT EXISTS (SELECT FROM pg_indexes WHERE indexname = 'idx_daily_counters_date_channel') THEN
        CREATE INDEX idx_daily_counters_date_channel ON daily_counters(date, channel_code);
    END IF;
END $$;

-- 9. 設定 RLS (Row Level Security) 政策
-- 啟用 RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE queue_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_counters ENABLE ROW LEVEL SECURITY;

-- 建立允許所有操作的政策（用於管理後台）
DROP POLICY IF EXISTS "Allow all operations for admin" ON orders;
CREATE POLICY "Allow all operations for admin" ON orders
    FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all operations for admin" ON order_items;
CREATE POLICY "Allow all operations for admin" ON order_items
    FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all operations for admin" ON queue_numbers;
CREATE POLICY "Allow all operations for admin" ON queue_numbers
    FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all operations for admin" ON daily_counters;
CREATE POLICY "Allow all operations for admin" ON daily_counters
    FOR ALL USING (true) WITH CHECK (true);

-- 10. 顯示升級結果
SELECT 'Database upgrade completed successfully!' as result; 