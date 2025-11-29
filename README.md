# Student Performance and Learning Style Analysis

## Project Assignment 1: Project proposal

## Team Members
- Lisa Sverdlova
- Aleksandra Szymula
- Alvin Lee
- Liru Chen

## Project Description
This project analyzes the relationship between students’ performance and their learning styles using a dataset from Kaggle.  
The goal is to apply big data techniques to identify patterns, correlations, and insights that may help improve learning outcomes.

## Dataset
We are using the **Student Performance and Learning Style** dataset, available here:  
[https://www.kaggle.com/datasets/adilshamim8/student-performance-and-learning-style](https://www.kaggle.com/datasets/adilshamim8/student-performance-and-learning-style)

The dataset gives information on each student's learning style, academic performance, and study methods.

For instructions on downloading the dataset, please see the [`/data/README.md`](data/README.md).

## Project Assignment 2:
### A) Data Card (markdown or README section)
*Source: Kaggle, "Student Performance and Learning Behavior Dataset"*

*Link: https://www.kaggle.com/datasets/adilshamim8/student-performance-and-learning-style*

*File Format: .csv*

*Compression: None*

*Row Count: 14003 rows*

*Column Count: 16 columns*

*Delimiter: ','*

*Header Presence: Header is present*

*Encoding: Regular file*

*Notes: No missing fields*

### B) Access & Snapshots (reproducible)

*If compressed: stream into commands (zcat, unzip -p) rather than fully extracting when possible: Not applicable as .csv file is not compressed*

## How to run script `pa6.py` as a job on a cloud environment (Google Cloud)
First, the project environment must be set up by doing the following:
1. Create a project.
2. Create a bucket.
3. Populate the bucket with input data (stored in `data/`), `pa6.py`, and a dependencies directory.
Next, open the terminal and do the following commands:
1. Define variables for the bucket name, the bucket's region, and the location of the code in the Google Cloud Storage (```$BUCKET, $REGION, $CODE_URI```).
2. Run this following command:
```
gcloud dataproc batches submit pyspark "$CODE_URI"   --region="$REGION"   --deps-bucket="gs://$BUCKET"   --properties="\
spark.dynamicAllocation.enabled=false,\
spark.driver.cores=4,\
spark.driver.memory=8g,\
spark.executor.instances=7,\
spark.executor.cores=4,\
spark.executor.memory=4g"
```
3. See figures of graphs in `out/` in the GCS.
* Input data: `gs://$BUCKET/data/`
* Output data: `gs://$BUCKET/out/`
