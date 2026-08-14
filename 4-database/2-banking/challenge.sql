/*
    Challenge: Implement a Secure Fund Transfer Function

    In this challenge, you will implement a PostgreSQL stored function to simulate transferring funds
    between two accounts in a banking system. The function must follow proper validation, ensure data
    integrity, and log transactions with a shared reference.

    Your function should be named:
    banking.transfer_funds(from_id INT, to_id INT, amount NUMERIC)

    The function must:

    - Prevent transfers to the same account
    - Ensure the transfer amount is greater than zero
    - Validate that both sender and recipient accounts exist
    - Prevent transfers if either account is marked as "frozen"
    - Ensure the sender has sufficient funds
    - Debit the sender and credit the recipient atomically
    - Log two transactions: a withdrawal and a deposit, both linked by the same UUID reference
    - Raise meaningful exceptions for all validation failures

    The function should perform all operations within a safe transactional context, maintaining
    database consistency even in the event of failure.

    Notes:
    - In order to test you can mock some additional data in the tables that participates in this challenge.
    - Make sure of raising errors when they're present

    ERD:
    +---------------------+            +--------------------------+
    |     accounts        |            |      transactions        |
    +---------------------+            +--------------------------+
    | account_id (PK)     |<-----------| transaction_id (PK)      |
    | balance             |            | account_id (FK)          |
    | status              |            | amount                   |
    +---------------------+            | transaction_type         |
                                       | reference                |
                                       | transaction_date         |
                                       +--------------------------+
*/


-- your solution here
CREATE OR REPLACE FUNCTION banking.transfer_funds(from_id INT, to_id INT, amount NUMERIC)
RETURNS VOID AS $$
DECLARE
  v_from_balance NUMERIC;
  v_from_status  TEXT;
  v_to_status    TEXT;
  v_ref          TEXT;
  v_first_id     INT;
  v_second_id    INT;
BEGIN
  IF from_id = to_id THEN
    RAISE EXCEPTION 'Cannot transfer to the same account (account_id=%)', from_id;
  END IF;

  IF amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be greater than zero, got %', amount;
  END IF;

  v_first_id  := LEAST(from_id, to_id);
  v_second_id := GREATEST(from_id, to_id);

  PERFORM 1 FROM banking.accounts WHERE account_id = v_first_id  FOR UPDATE;
  PERFORM 1 FROM banking.accounts WHERE account_id = v_second_id FOR UPDATE;

  SELECT balance, status INTO v_from_balance, v_from_status
  FROM banking.accounts WHERE account_id = from_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sender account % does not exist', from_id;
  END IF;

  SELECT status INTO v_to_status
  FROM banking.accounts WHERE account_id = to_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipient account % does not exist', to_id;
  END IF;

  IF v_from_status = 'frozen' THEN
    RAISE EXCEPTION 'Sender account % is frozen', from_id;
  END IF;

  IF v_to_status = 'frozen' THEN
    RAISE EXCEPTION 'Recipient account % is frozen', to_id;
  END IF;

  IF v_from_balance < amount THEN
    RAISE EXCEPTION 'Insufficient funds in account %: balance %, requested %', from_id, v_from_balance, amount;
  END IF;

  UPDATE banking.accounts SET balance = balance - amount WHERE account_id = from_id;
  UPDATE banking.accounts SET balance = balance + amount WHERE account_id = to_id;

  v_ref := gen_random_uuid()::text;

  INSERT INTO banking.transactions (account_id, amount, transaction_type, reference)
  VALUES (from_id, amount, 'withdrawal', v_ref);

  INSERT INTO banking.transactions (account_id, amount, transaction_type, reference)
  VALUES (to_id, amount, 'deposit', v_ref);
END;
$$ LANGUAGE plpgsql;
