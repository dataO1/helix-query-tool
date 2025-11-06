// DEFINITIONS

// Add and index a document - automatic chunking by backend
QUERY add_document(filepath: String, content: String, filetype: String, metadata: Json) =>
  doc <- AddDocument({
    filepath: filepath,
    content: content,
    filetype: filetype,
    metadata: metadata
  })
  RETURN doc

// Semantic text search with embedding
QUERY search_with_text(query: String, limit: I32) =>
  results <- SearchWithText({
    query: query,
    limit: limit
  })
  RETURN results

// Keyword search on filenames and metadata
QUERY search_keyword(keywords: [String], limit: I32) =>
  results <- SearchKeyword({
    keywords: keywords,
    limit: limit
  })
  RETURN results

// List all indexed files with optional limit
QUERY list_indexed_files(limit: I32) =>
  files <- ListIndexedFiles({
    limit: limit
  })
  RETURN files

// Retrieve full content of a file by path
QUERY get_file_content(filepath: String) =>
  content <- GetFileContent({
    filepath: filepath
  })
  RETURN content

// Retrieve metadata about a file by path
QUERY get_file_metadata(filepath: String) =>
  metadata <- GetFileMetadata({
    filepath: filepath
  })
  RETURN metadata

// Indexing statistics and info
QUERY get_index_stats() =>
  stats <- GetIndexStats({})
  RETURN stats
