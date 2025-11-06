// Flexible document schema for file indexing
N::Document {
  INDEX filepath: String,
  content: String,
  filetype: String,
  metadata: Json,
  created_at: Date DEFAULT NOW
}
