package database

import (
	"database/sql"
	"embed"
	"log"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

func Migrate(db *sql.DB) error {
	data, err := migrationFiles.ReadFile("migrations/001_create_tables.sql")
	if err != nil {
		return err
	}

	_, err = db.Exec(string(data))
	if err != nil {
		return err
	}

	log.Println("Database migration completed")
	return nil
}
