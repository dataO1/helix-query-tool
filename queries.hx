// Add and index a document using vector embedding
QUERY add_document(filepath: String, content: String, filetype: String, metadata: Json) =>
  doc <- AddV<Document>({
    filepath: filepath,
    content: content,
    filetype: filetype,
    metadata: metadata,
    embedding: Embed(content)
  })
  RETURN doc

// Semantic text search with embedding
QUERY search_with_text(query: String, limit: I64) =>
  results <- SearchV<Document>(Embed(query), limit)
  RETURN results

// Keyword search on metadata (with postfiltering)
QUERY search_keyword(keywords: [String], limit: I64) =>
  results <- SearchV<Document>(Embed(keywords[0]), limit)
  ::WHERE(_::{metadata}::CONTAINS(keywords))
  RETURN results

// List indexed files - requires traversal
QUERY list_indexed_files(limit: I64) =>
  files <- All<Document>()
  RETURN files

// Retrieve file by path
QUERY get_file_content(filepath: String) =>
  content <- All<Document>()
  ::WHERE(_::{filepath}::EQ(filepath))
  RETURN content

// Retrieve file metadata by path
QUERY get_file_metadata(filepath: String) =>
  metadata <- All<Document>()
  ::WHERE(_::{filepath}::EQ(filepath))
  RETURN metadata::{filepath, metadata, filetype}

// Indexing statistics - may not exist in HelixQL
// You may need to implement this differently via SDK
QUERY get_index_stats() =>
  count <- Count<Document>()
  RETURN count
