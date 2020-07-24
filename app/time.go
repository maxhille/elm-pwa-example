package app

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"log"
	"time"
)

type Time struct {
	time.Time
}

func (t *Time) UnmarshalJSON(b []byte) error {
	var ms int64
	err := json.Unmarshal(b, &ms)
	if err != nil {
		return err
	}

	t = fromMillis(ms)

	return nil
}

func (t Time) MarshalJSON() ([]byte, error) {
	return json.Marshal(t.toMillis())
}

func (t Time) Value() (driver.Value, error) {
	log.Print("Value()")
	return t.toMillis(), nil
}

func (t *Time) Scanner(src interface{}) error {
	log.Print("Scanner()")
	ms, ok := src.(int64)
	if !ok {
		return fmt.Errorf("expected int64, but got %v", src)
	}
	t = fromMillis(ms)
	return nil
}

func fromMillis(ms int64) *Time {
	return &Time{time.Unix(0, ms*int64(time.Millisecond))}
}

func (t Time) toMillis() int64 {
	return t.UnixNano() / int64(time.Millisecond)
}
