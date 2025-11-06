// Semantic text search with embedding
QUERY search_with_text(query: String, limit: I64) =>
  results <- SearchV<Document>(Embed(query), limit)
  RETURN results

// Keyword search (NOTE: SearchV doesn't exist for keyword; use traversal instead)
QUERY search_keyword(keywords: [String], limit: I64) =>
  results <- All<Document>()
  ::WHERE(_::{metadata}::CONTAINS(keywords[0]))
  RETURN results

// List indexed files
QUERY list_indexed_files(limit: I64) =>
  files <- All<Document>()
  RETURN files

// Retrieve file by path (use traversal + filter, not All)
QUERY get_file_content(filepath: String) =>
  doc <- All<Document>()
  ::WHERE(_::{filepath}::EQ(filepath))
  RETURN doc::{content}

// Retrieve file metadata by path
QUERY get_file_metadata(filepath: String) =>
  doc <- All<Document>()
  ::WHERE(_::{filepath}::EQ(filepath))
  RETURN doc::{filepath, metadata, filetype}

// Indexing statistics (count nodes)
QUERY get_index_stats() =>
  count <- All<Document>()
  RETURN count
