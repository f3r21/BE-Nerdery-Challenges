CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE SCHEMA IF NOT EXISTS banking;

CREATE TABLE banking.accounts (
    account_id SERIAL PRIMARY KEY,
    balance NUMERIC(12, 2) DEFAULT 0 CHECK (balance >= 0),
    status TEXT NOT NULL CHECK (status IN ('active', 'frozen'))
);

CREATE TABLE banking.transactions (
    transaction_id SERIAL PRIMARY KEY,
    account_id INT NOT NULL REFERENCES banking.accounts(account_id),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal')),
    reference TEXT,
    transaction_date TIMESTAMP DEFAULT NOW()
);



INSERT INTO banking.accounts (account_id, balance, status)
VALUES 
  (1, 1000.00, 'active'),
  (2, 500.00, 'active'),
  (3, 40000, 'frozen')    