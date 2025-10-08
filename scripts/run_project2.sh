# Dataset path: /mnt/scratch/CS131_jelenag/projects/team08_sec3/student_performance.csv
# Delimiter: comma (,)
# Assumptions: 
# - student_performance.csv is located in Group-8-Education-Data/scripts when executing run_project2.sh

#!/bin/bash
# (head -n 1  student_performance.csv ; tail -n +2  student_performance.csv | shuf -n 1000) > ../data/samples/student_performance_1k_sample.csv

# Generate frequency of resources (...)
tail -n+2 student_performance.csv | cut -d ',' -f3 | sort | uniq -c | sort -nr | tee ../out/freq_resources.txt ; echo -e "\n"

# Generate frequency of gender (0 - male; 1 - female)
tail -n+2 student_performance.csv | cut -d ',' -f7 | sort | uniq -c | sort -nr | tee ../out/freq_gender.txt ; echo -e "\n"

# Generate frequency of internet usage (0 - no; 1 - yes)
tail -n+2 student_performance.csv | cut -d ',' -f6 | sort | uniq -c | sort -nr | tee ../out/freq_internet.txt ; echo -e "\n"

# Generate frequency of learning style (...)
tail -n+2 student_performance.csv | cut -d ',' -f9 | sort | uniq -c | sort -nr | tee ../out/freq_learningstyle.txt ; echo -e "\n"

# Generate top 10 most common weekly study hours
tail -n+2 student_performance.csv | cut -d ',' -f1 | sort | uniq -c | sort -nr | head -10 | tee ../out/top10_weekly_studyhours.txt ; echo -e "\n"

# Generate a skinny table with columns attendance, extracurricular activities (0 - yes; 1 - no), and exam scores
tail -n+2 student_performance.csv | cut -d ',' -f2,4,13 | sort -u > out/attendance_ec_examscr.txt 2> ../out/errors.txt

# Filter ranges of exam scores
grep -Ei "*,*,6+" ../out/attendance_ec_examscr.txt > ../out/exam_scores_60s.txt 2>> ../out/errors.txt
grep -Ev "*,*,(9+|100)" ../out/attendance_ec_examscr.txt > ../out/exam_scores_90s_less.txt 2>> ../out/errors.txt

echo "Script ran successfully!" > ../out/success.log 2> ../out/errors.log
