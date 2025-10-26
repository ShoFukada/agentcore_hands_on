# Data sources for AWS account info
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# API Key Credential Provider for Tavily
resource "aws_bedrockagentcore_api_key_credential_provider" "tavily" {
  name   = var.tavily_credential_provider_name
  api_key = var.tavily_api_key
}

# Gateway Resource
resource "aws_bedrockagentcore_gateway" "main" {
  name        = var.gateway_name
  description = var.description
  role_arn    = var.gateway_role_arn

  authorizer_type = var.authorizer_type
  protocol_type   = var.protocol_type

  # Note: According to AWS API docs, authorizer_configuration is only required for CUSTOM_JWT
  # For AWS_IAM, it should not be provided
  # However, Terraform provider seems to require it - this might be a provider bug

  tags = var.tags
}


# Tavily OpenAPI Schema definition
locals {
  tavily_openapi_schema = jsonencode({
    openapi = "3.0.0"
    info = {
      title       = "Tavily Search API"
      description = "Tavily search and extract API"
      version     = "1.0.0"
    }
    servers = [
      {
        url = "https://api.tavily.com"
      }
    ]
    paths = {
      "/search" = {
        post = {
          operationId = "TavilySearchPost"
          summary     = "Execute a search query using Tavily Search"
          description = "Search the web using Tavily API"
          requestBody = {
            required = true
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  required = ["query"]
                  properties = {
                    query = {
                      type        = "string"
                      description = "The search query to execute"
                    }
                    auto_parameters = {
                      type        = "boolean"
                      description = "Automatically configure search parameters based on query intent"
                      default     = false
                    }
                    topic = {
                      type        = "string"
                      description = "Search category"
                      enum        = ["general", "news", "finance"]
                      default     = "general"
                    }
                    search_depth = {
                      type        = "string"
                      description = "Search depth: basic (1 credit) or advanced (2 credits)"
                      enum        = ["basic", "advanced"]
                      default     = "basic"
                    }
                    chunks_per_source = {
                      type        = "integer"
                      description = "Maximum content snippets per source"
                      default     = 3
                      minimum     = 1
                      maximum     = 3
                    }
                    max_results = {
                      type        = "integer"
                      description = "Maximum number of results to return"
                      default     = 5
                      minimum     = 0
                      maximum     = 20
                    }
                    time_range = {
                      type        = "string"
                      description = "Filter by timeframe: day, week, month, year"
                      enum        = ["day", "week", "month", "year"]
                    }
                    start_date = {
                      type        = "string"
                      description = "Start date for date range filtering (YYYY-MM-DD format)"
                      pattern     = "^\\d{4}-\\d{2}-\\d{2}$"
                    }
                    end_date = {
                      type        = "string"
                      description = "End date for date range filtering (YYYY-MM-DD format)"
                      pattern     = "^\\d{4}-\\d{2}-\\d{2}$"
                    }
                    include_answer = {
                      type        = "boolean"
                      description = "Include LLM-generated answer"
                      default     = false
                    }
                    include_raw_content = {
                      type        = "boolean"
                      description = "Include parsed HTML content"
                      default     = false
                    }
                    include_images = {
                      type        = "boolean"
                      description = "Include image search results"
                      default     = false
                    }
                    include_image_descriptions = {
                      type        = "boolean"
                      description = "Add descriptions to images"
                      default     = false
                    }
                    include_favicon = {
                      type        = "boolean"
                      description = "Include favicon URLs"
                      default     = false
                    }
                    include_domains = {
                      type        = "array"
                      description = "List of domains to include in search (max 300)"
                      maxItems    = 300
                      items = {
                        type = "string"
                      }
                    }
                    exclude_domains = {
                      type        = "array"
                      description = "List of domains to exclude from search (max 150)"
                      maxItems    = 150
                      items = {
                        type = "string"
                      }
                    }
                    country = {
                      type        = "string"
                      description = "Boost results from specific country (ISO 3166-1 alpha-2 code)"
                    }
                  }
                }
              }
            }
          }
          responses = {
            "200" = {
              description = "Successful search response"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      query = {
                        type = "string"
                      }
                      answer = {
                        type = "string"
                      }
                      images = {
                        type = "array"
                        items = {
                          type = "object"
                          properties = {
                            url         = { type = "string" }
                            description = { type = "string" }
                          }
                        }
                      }
                      results = {
                        type = "array"
                        items = {
                          type = "object"
                          properties = {
                            title       = { type = "string" }
                            url         = { type = "string" }
                            content     = { type = "string" }
                            score       = { type = "number" }
                            raw_content = { type = "string" }
                            favicon     = { type = "string" }
                          }
                        }
                      }
                      auto_parameters = {
                        type = "object"
                      }
                      response_time = {
                        type = "number"
                      }
                      request_id = {
                        type = "string"
                      }
                    }
                  }
                }
              }
            }
            "400" = {
              description = "Invalid request parameters"
            }
            "401" = {
              description = "Missing or invalid API key"
            }
            "429" = {
              description = "Rate limit exceeded"
            }
            "500" = {
              description = "Server error"
            }
          }
          security = [
            {
              ApiKeyAuth = []
            }
          ]
        }
      }
      "/extract" = {
        post = {
          operationId = "TavilySearchExtract"
          summary     = "Extract webpage content from URLs using Tavily Extract"
          description = "Extract content from URLs (max 20 URLs)"
          requestBody = {
            required = true
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  required = ["urls"]
                  properties = {
                    urls = {
                      oneOf = [
                        {
                          type        = "string"
                          description = "Single URL to extract content from"
                        },
                        {
                          type        = "array"
                          description = "List of URLs to extract content from (max 20)"
                          maxItems    = 20
                          items = {
                            type = "string"
                          }
                        }
                      ]
                    }
                    include_images = {
                      type        = "boolean"
                      description = "Include a list of images extracted from the URLs"
                      default     = false
                    }
                    include_favicon = {
                      type        = "boolean"
                      description = "Include favicon URL for each result"
                      default     = false
                    }
                    extract_depth = {
                      type        = "string"
                      description = "Extraction depth: basic or advanced (retrieves tables/embedded content)"
                      enum        = ["basic", "advanced"]
                      default     = "basic"
                    }
                    format = {
                      type        = "string"
                      description = "Output format: markdown or text"
                      enum        = ["markdown", "text"]
                      default     = "markdown"
                    }
                    timeout = {
                      type        = "number"
                      description = "Timeout in seconds (1.0-60.0). Defaults: 10s (basic), 30s (advanced)"
                      minimum     = 1.0
                      maximum     = 60.0
                    }
                  }
                }
              }
            }
          }
          responses = {
            "200" = {
              description = "Successful extraction"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      results = {
                        type = "array"
                        items = {
                          type = "object"
                          properties = {
                            url         = { type = "string" }
                            raw_content = { type = "string" }
                            images = {
                              type = "array"
                              items = {
                                type = "string"
                              }
                            }
                            favicon = { type = "string" }
                          }
                        }
                      }
                      failed_results = {
                        type = "array"
                        items = {
                          type = "string"
                        }
                      }
                      response_time = {
                        type = "number"
                      }
                      request_id = {
                        type = "string"
                      }
                    }
                  }
                }
              }
            }
            "400" = {
              description = "Bad request (e.g., exceeds URL limit)"
            }
            "401" = {
              description = "Invalid or missing API key"
            }
            "429" = {
              description = "Rate limit exceeded"
            }
            "500" = {
              description = "Server error"
            }
          }
          security = [
            {
              ApiKeyAuth = []
            }
          ]
        }
      }
    }
    components = {
      securitySchemes = {
        ApiKeyAuth = {
          type = "apiKey"
          in   = "header"
          name = "Authorization"
        }
      }
    }
  })
}

resource "aws_bedrockagentcore_gateway_target" "tavily" {
  name               = var.tavily_target_name
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = var.tavily_target_description

  # Use API Key authentication
  credential_provider_configuration {
    api_key {
      provider_arn              = aws_bedrockagentcore_api_key_credential_provider.tavily.credential_provider_arn
      credential_location       = "HEADER"
      credential_parameter_name = "Authorization"
      credential_prefix         = "Bearer "
    }
  }

  # OpenAPI schema-based target configuration
  target_configuration {
    mcp {
      open_api_schema {
        inline_payload {
          payload = local.tavily_openapi_schema
        }
      }
    }
  }
}
