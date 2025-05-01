# Database Module Exercises

This repository contains the challenges for the Database module, designed to test and enhance your understanding of SQL queries and transactions.

## Structure

1. **Pagila:** In this exercise you will be provided with a database configured for movie rental information. Your task is to solve each of the queries provided.

2. **Banking:** In this exercise you're provided with the tables account and transaction to simulate a function for handling transactions.

## Getting Started

This folder contains a docker compose file that will start up the database for Pagila and also will create a separate schema for the banking exercise.

### Prerequisites:

- Install Docker Desktop
- Have your PostgreSQL client of your preference

### Steps:

1. Run `docker-compose up` inside of this folder to mount the container and the data for your database.

2. If everything goes well you can open the client of your preference using the following credentials:

```
POSTGRES_PASSWORD: pass_nerdery
POSTGRES_USER: postgres
POSTGRES_DB: nerdery_db
```

### Alternative Setup

In case you have problems installing Docker, you can easily install the PostgreSQL server and client of your preference and create a database on it.

Then you can execute the SQL files in the same order that exists in the `init.db` folder:

```
01-pagila-schema.sql
02-pagila-data.sql
03-transactions.sql
```
