# docker cp amazon_reviews.csv r-hadoop-container:/home/hdfs/amazon_reviews.csv
# Complete Hadoop Streaming Analysis of Amazon Reviews Dataset with Single-Column CSV

Sys.setenv(HADOOP_HOME = "/opt/hadoop")
Sys.setenv(HADOOP_CMD = "/opt/hadoop/bin/hadoop")
Sys.setenv(JAVA_HOME = "/usr/lib/jvm/java-8-openjdk-amd64")

if(!file.exists("amazon_reviews.csv")) {
  stop("Error: amazon_reviews.csv file not found in the current directory")
}

# Check the file size
file_info <- file.info("amazon_reviews.csv")
cat("Dataset size:", file_info$size, "bytes\n")

# Upload the data to HDFS
system("$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hdfs/amazon_reviews")
system("$HADOOP_HOME/bin/hdfs dfs -put amazon_reviews.csv /user/hdfs/amazon_reviews/")

# Remove output directory if it exists
system("$HADOOP_HOME/bin/hdfs dfs -test -d /user/hdfs/amazon_reviews_output && $HADOOP_HOME/bin/hdfs dfs -rm -r /user/hdfs/amazon_reviews_output")

# Create mapper script for sentiment analysis
writeLines('#!/usr/bin/env Rscript

positive_words <- c("good", "great", "excellent", "delicious", "love", "best", "tasty", "amazing", 
                    "favorite", "perfect", "wonderful", "enjoyed", "recommend", "fantastic", 
                    "awesome", "superb", "happy", "pleased", "impressed", "satisfied", "clean",
                    "yay", "ideal", "better", "bonus", "recommend", "perfect", "focused", "centered",
                    "energized", "relaxed", "delicate", "delicious", "rich", "treat", "enjoy")

negative_words <- c("bad", "terrible", "awful", "horrible", "worst", "hate", "disgusting", 
                    "poor", "disappointing", "dislike", "nasty", "waste", "regret", "bland", 
                    "mediocre", "avoid", "unfortunately", "disappointed", "tasteless", "upset",
                    "annoyance", "unnecessary", "tough", "lost", "concerned", "stale", "nasty",
                    "chemical", "artificial", "picky", "odd", "strange")

# Process input from stdin (single-column CSV format)
input <- file("stdin", "r")
header <- TRUE
line_count <- 0

while(length(line <- readLines(input, n = 1)) > 0) {
  line_count <- line_count + 1
  
  # Skip header row if present
  if(header) {
    header <- FALSE
    # If you want to check if the line looks like a header
    if(tolower(line) == "text") {
      next  # Skip this iteration and proceed to the next line
    }
  }
  
  # For the specific CSV structure provided, there\'s only one column
  review_text <- line
  
  # Strip any surrounding quotes
  review_text <- gsub("^\\"|\\"$", "", review_text)
  
  # Handle HTML tags
  review_text <- gsub("<[^>]*>", " ", review_text)
  
  # Convert to lowercase and split into words
  words <- tolower(gsub("[[:punct:]]", "", review_text))
  words <- unlist(strsplit(words, "\\\\s+"))
  
  # Count positive and negative words in this review
  positive_count <- sum(words %in% positive_words)
  negative_count <- sum(words %in% negative_words)
  
  # Use line number as review ID
  review_id <- paste("review", line_count, sep="_")
  
  # For word frequency analysis (optional)
  for(word in words) {
    if(nchar(word) > 0) {  # Skip empty words
      cat("WORD_", word, "\\t1\\n", sep="")
    }
  }
  
  # Output one sentiment classification per review
  if(positive_count > negative_count) {
    cat("REVIEW_", review_id, "\\tpositive\\n", sep="")
  } else if(negative_count > positive_count) {
    cat("REVIEW_", review_id, "\\tnegative\\n", sep="")
  } else if(positive_count > 0 || negative_count > 0) {
    # Equal positive and negative counts but not zero
    cat("REVIEW_", review_id, "\\tneutral\\n", sep="")
  } else {
    # No sentiment words found
    cat("REVIEW_", review_id, "\\tunknown\\n", sep="")
  }
}
close(input)
', "sentiment_mapper.R")

# Create reducer script (unchanged from previous version)
writeLines('#!/usr/bin/env Rscript
library(plyr)

input <- file("stdin", "r")
word_counts <- list()
sentiment_counts <- list()

while(length(line <- readLines(input, n = 1)) > 0) {
  parts <- strsplit(line, "\\t")[[1]]
  key <- parts[1]
  value <- parts[2]
  
  if(startsWith(key, "WORD_")) {
    # Handle word count aggregation
    word <- substring(key, 6)  # Remove "WORD_" prefix
    count <- as.integer(value)
    
    if(is.null(word_counts[[word]])) {
      word_counts[[word]] <- count
    } else {
      word_counts[[word]] <- word_counts[[word]] + count
    }
  } else if(startsWith(key, "REVIEW_")) {
    # Handle sentiment aggregation
    sentiment <- value
    
    if(is.null(sentiment_counts[[sentiment]])) {
      sentiment_counts[[sentiment]] <- 1
    } else {
      sentiment_counts[[sentiment]] <- sentiment_counts[[sentiment]] + 1
    }
  }
}

# Output sentiment summary
cat("\\n==== SENTIMENT SUMMARY ====\\n")
sentiments <- names(sentiment_counts)
for(sentiment in sentiments) {
  count <- sentiment_counts[[sentiment]]
  cat(sentiment, "\\t", count, "\\n", sep="")
}

close(input)
', "sentiment_reducer.R")

system("chmod +x sentiment_mapper.R sentiment_reducer.R")

# Run Hadoop Streaming job
cmd <- paste(
  "$HADOOP_HOME/bin/hadoop jar $HADOOP_HOME/share/hadoop/tools/lib/hadoop-streaming-3.3.6.jar",
  "-files sentiment_mapper.R,sentiment_reducer.R",
  "-input /user/hdfs/amazon_reviews/amazon_reviews.csv",
  "-output /user/hdfs/amazon_reviews_output",
  "-mapper sentiment_mapper.R",
  "-reducer sentiment_reducer.R"
)
system(cmd)

# Get the results from HDFS
system("$HADOOP_HOME/bin/hdfs dfs -cat /user/hdfs/amazon_reviews_output/part-*")
system("$HADOOP_HOME/bin/hdfs dfs -get /user/hdfs/amazon_reviews_output/part-* results.txt")

cat("\n\nResults saved to results.txt\n")