# hadoop Mapreduce with hardcoded reviews
# Set up environment variables
Sys.setenv(HADOOP_HOME = "/opt/hadoop")
Sys.setenv(HADOOP_CMD = "/opt/hadoop/bin/hadoop")
Sys.setenv(JAVA_HOME = "/usr/lib/jvm/java-8-openjdk-amd64")

set.seed(123)
reviews <- c(
  "This pasta sauce is amazing! Great flavor and texture.",
  "Worst chocolate I've ever tasted. Very disappointing and expensive.",
  "The coffee beans produce a wonderful aroma. Highly recommend!",
  "Not happy with these chips. They were stale and tasteless.",
  "Perfect snack for hiking. Love the mix of nuts and dried fruits.",
  "Mediocre at best. The spices were bland and underwhelming.",
  "Delicious organic honey, best I've ever had! Worth every penny.",
  "These cookies were hard as rocks. Terrible quality control.",
  "Amazing flavor in this hot sauce. Excellent on everything!",
  "Regret buying this cereal. Too sweet and artificial tasting."
)

# Write to text file
writeLines(reviews, "reviews_text.txt")

# Check the file size
file_info <- file.info("reviews_text.txt")
cat("Dataset size:", file_info$size, "bytes\n")

# Upload the data to HDFS
system("$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hdfs/amazon_reviews")
system("$HADOOP_HOME/bin/hdfs dfs -put reviews_text.txt /user/hdfs/amazon_reviews/")

# Remove output directory if it exists
system("$HADOOP_HOME/bin/hdfs dfs -test -d /user/hdfs/amazon_reviews_output && $HADOOP_HOME/bin/hdfs dfs -rm -r /user/hdfs/amazon_reviews_output")

# mapper script for sentiment analysis
writeLines('#!/usr/bin/env Rscript

positive_words <- c("good", "great", "excellent", "delicious", "love", "best", "tasty", "amazing", "favorite", "perfect", "wonderful", "enjoyed", "recommend", "fantastic", "awesome", "superb", "happy", "pleased", "impressed", "satisfied")

negative_words <- c("bad", "terrible", "awful", "horrible", "worst", "hate", "disgusting", "poor", "disappointing", "dislike", "nasty", "waste", "regret", "bland", "mediocre", "avoid", "unfortunately", "disappointed", "tasteless", "upset")

input <- file("stdin", "r")
while(length(line <- readLines(input, n = 1)) > 0) {
  # Convert to lowercase and split into words
  words <- tolower(gsub("[[:punct:]]", "", line))
  words <- unlist(strsplit(words, "\\\\s+"))
  
  # Count positive and negative words in this review
  positive_count <- sum(words %in% positive_words)
  negative_count <- sum(words %in% negative_words)
  
  # Determine overall sentiment for the review
  review_id <- sample(1:1000000, 1)  # Generate a unique ID for each review
  
  # For word frequency analysis (optional)
  for(word in words) {
    cat("WORD_", word, "\\t1\\n", sep="")
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

# reducer script
writeLines('#!/usr/bin/env Rscript

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

# Output word frequency counts
cat("\\n==== WORD FREQUENCIES ====\\n")
word_list <- names(word_counts)
word_count_list <- unlist(word_counts)
word_sorted_indices <- order(word_count_list, decreasing = TRUE)

for(i in word_sorted_indices) {
  word <- word_list[i]
  count <- word_count_list[i]
  cat(word, "\\t", count, "\\n", sep="")
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

# Make scripts executable
system("chmod +x sentiment_mapper.R sentiment_reducer.R")

# Run Hadoop Streaming job
cmd <- paste(
  "$HADOOP_HOME/bin/hadoop jar $HADOOP_HOME/share/hadoop/tools/lib/hadoop-streaming-3.3.6.jar",
  "-files sentiment_mapper.R,sentiment_reducer.R",
  "-input /user/hdfs/amazon_reviews/reviews_text.txt",
  "-output /user/hdfs/amazon_reviews_output",
  "-mapper sentiment_mapper.R",
  "-reducer sentiment_reducer.R"
)
system(cmd)

# Get the results from HDFS
system("$HADOOP_HOME/bin/hdfs dfs -cat /user/hdfs/amazon_reviews_output/part-*")

# Save results to a local file for further analysis
system("$HADOOP_HOME/bin/hdfs dfs -get /user/hdfs/amazon_reviews_output/part-* results.txt")

# Print analysis summary
cat("\n\nResults saved to results.txt\n")