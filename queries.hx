// Semantic text search with embedding
QUERY search_with_text(query: String, limit: I64) =>
  results <- SearchV<Document>(query, limit)
  RETURN results

//QUERY search_keyword(keywords: String, limit: I64) =>
  //results <- SearchBM25<Document>(keywords, limit)
  //RETURN results

// List indexed files
QUERY list_indexed_files(limit: I64) =>
  files <- V<Document>
  RETURN files

// Retrieve file by path (use traversal + filter, not All)
QUERY get_file_content(filepath: String) =>
  doc <- V<Document>
  ::WHERE(_::{filepath}::EQ(filepath))
  RETURN doc::{content}

// Retrieve file metadata by path
QUERY get_file_metadata(filepath: String) =>
  doc <- V<Document>
  ::WHERE(_::{filepath}::EQ(filepath))
  RETURN doc::{filepath, metadata, filetype}

// Indexing statistics (count nodes)
QUERY get_index_stats() =>
  count <- V<Document>::COUNT
  RETURN count
