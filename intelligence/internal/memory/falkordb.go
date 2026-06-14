// falkordb.go — FalkorDB graph query client via Redis RESP protocol.
//
// Purpose: Execute Cypher queries against FalkorDB to retrieve temporally-valid
//          fact triples for graph-based retrieval (third lane in the RRF pipeline).
//          Gracefully skips all graph operations when NCLAW_FALKORDB_URL is unset.
// Inputs:  userID UUID, sourceAccountID string, optional limit int.
// Outputs: []graphFact — subject/predicate/object triples (fact IDs for RRF).
// Constraints: Uses redis/go-redis only for RESP transport. No FalkorDB SDK dep.
//              Graceful skip (not panic) on empty NCLAW_FALKORDB_URL. ≤150 lines.
// SPORT: nclaw-memory-architecture-spec.md §6 — FalkorDB graph traversal path.
package memory

import (
	"context"
	"fmt"
	"os"

	"github.com/redis/go-redis/v9"
)

// graphFact is a fact triple retrieved from FalkorDB.
type graphFact struct {
	// FactID is the FalkorDB node property used as the RRF doc ID.
	FactID string
	// Subject is the fact subject string.
	Subject string
	// Predicate is the fact relationship type.
	Predicate string
	// Object is the fact object string.
	Object string
}

// falkorClient returns a go-redis client pointed at NCLAW_FALKORDB_URL.
// Returns nil when the URL is unset — callers must check for nil before using.
func falkorClient() *redis.Client {
	addr := os.Getenv("NCLAW_FALKORDB_URL")
	if addr == "" {
		return nil
	}
	return redis.NewClient(&redis.Options{
		Addr: addr,
	})
}

// GraphQuery retrieves current (non-expired) fact nodes connected to the given user.
//
// Cypher query per spec §6:
//   MATCH (u:User {user_id: $userId})-[:KNOWS]->(f:Fact)
//   WHERE f.valid_until IS NULL OR f.valid_until > timestamp()
//   RETURN f.id, f.subject, f.predicate, f.object LIMIT $limit
//
// Returns an empty slice (not an error) when:
//   - NCLAW_FALKORDB_URL is unset (graceful skip)
//   - No facts exist for the user
//   - FalkorDB is unreachable (treated as non-fatal — BM25+dense still run)
//
// A non-nil error is returned only for structural decode failures where the
// returned data is malformed beyond what empty-slice default handles.
func GraphQuery(ctx context.Context, userID string, limit int) ([]graphFact, error) {
	client := falkorClient()
	if client == nil {
		// NCLAW_FALKORDB_URL not set — graph path skipped per spec §6.
		return nil, nil
	}
	defer client.Close()

	if limit <= 0 {
		limit = 20
	}

	// FalkorDB GRAPH.QUERY command: GRAPH.QUERY <graph_name> <cypher>
	// Graph name follows the namespace pattern: "nclaw:{userID}".
	graphName := fmt.Sprintf("nclaw:%s", userID)
	cypher := fmt.Sprintf(
		`MATCH (u:User {user_id: '%s'})-[:KNOWS]->(f:Fact) `+
			`WHERE f.valid_until IS NULL OR f.valid_until > timestamp() `+
			`RETURN f.id, f.subject, f.predicate, f.object LIMIT %d`,
		userID, limit,
	)

	// GRAPH.QUERY returns: [[header_row], [data_rows...], [stats]]
	raw, err := client.Do(ctx, "GRAPH.QUERY", graphName, cypher).Result()
	if err != nil {
		// Non-fatal: FalkorDB unreachable — return empty (BM25+dense still run).
		return nil, nil
	}

	// Parse FalkorDB result: []interface{} with 3 elements.
	rows, ok := raw.([]interface{})
	if !ok || len(rows) < 2 {
		return nil, nil
	}

	// Element 1 is the data rows: []interface{} of row slices.
	dataRows, ok := rows[1].([]interface{})
	if !ok {
		return nil, nil
	}

	facts := make([]graphFact, 0, len(dataRows))
	for _, rowRaw := range dataRows {
		row, ok := rowRaw.([]interface{})
		if !ok || len(row) < 4 {
			continue
		}
		facts = append(facts, graphFact{
			FactID:    fmt.Sprintf("%v", row[0]),
			Subject:   fmt.Sprintf("%v", row[1]),
			Predicate: fmt.Sprintf("%v", row[2]),
			Object:    fmt.Sprintf("%v", row[3]),
		})
	}
	return facts, nil
}
