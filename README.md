# infer-neo4j-schema-rb
This program takes a Neo4j database schema description and converts it
to a possible class hierarchy.

It is possibile to export results as UML using [PlantUML](https://plantuml.com/).

## Usage
This program reads the result of a
specific Cypher query in `cypher-shell`'s `--format plain` format.

Usage using pipes:
```
cypher-shell "MATCH (n) RETURN DISTINCT labels(n), keys(n)" | ruby infer_neo4j_schema.rb
```

Full pipeline from `cypher-shell` to a PNG:
```
cypher-shell "MATCH (n) RETURN DISTINCT labels(n), keys(n)" | ruby infer_neo4j_schema.rb | plantuml -p > classes.png
```
