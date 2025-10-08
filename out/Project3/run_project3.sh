





header=$(head -n 1 student_performance.csv)
col1_index=$(echo "$header" | awk -F ',' '{for(i=1;i<=NF;i++) {if($i=="Attendance") print i}}')
col2_index=$(echo "$header" | awk -F ',' '{for(i=1;i<=NF;i++) {if($i=="Motivation") print i}}')
awk -F ',' -v c1="$col1_index" -v c2="$col2_index" '{print $c1 "\t" $c2 | "(head -n 1 && tail -n +2 | sort -n -k 1)"}' student_performance.csv  > edges.tsv

(echo -n  -e "Count\t" | cat - <( head -n 1 edges.tsv | cut -f 1); tail -n +2 edges.tsv | cut -f 1 | uniq -c) > entity_counts.tsv

string=$(tail -n +2 entity_counts.tsv  | awk '$1 >= 350 {print $2}')
array=($string)

awk -F '\t' -v a="$string" 'BEGIN {split(a, array, " ");}
{
    flag = 0; 
    for (num in array)
 	{
       		 if (array[num] == $1)
 {
           	 flag = 1;
           	 break;
       		 }
    	}
    	if (flag == 1)
{
        	print $0;
}
}' edges.tsv > edges_thresholded.tsv

awk '($N1 + 0) >= 350 {print}' entity_counts.tsv > cluster_sizes.tsv

sort -t$'\t' -k2 -nr entity_counts.tsv | head -30 > top30_counts.txt
ls -l ~/Downloads/top30_counts.txt
head -10 top30_counts.txt
awk -F'\t' -v count="$COUNTS" '$1 == count' top30_counts.txt > top30_counts.tsv
sort -t$'\t' -k2 -nr entity_counts.tsv | head -30 > top30_counts.tsv
ls -lh top30_counts.tsv
head -5 top30_counts.tsv
tail -n +2 student_performance.csv | tr ',' '\n' | sort | uniq -c | sort -nr | head -30 > top30_overall.txt
diff top30_counts.txt top30_overall.txt > diff_top30.txt

edges_thresholded.tsv > cluster_edges.tsv
head cluster_edges.tsv
wc -l cluster_edges.tsv
tail -n +2 student_performance.tsv | nl -w1 -s$'\t' > student_performance_indexed.tsv
head -3 student_performance_indexed.tsv
cut -f1,17 student_performance_indexed.tsv > id_grade.tsv
head id_grade.tsv
sort -k2,2 edges_thresholded.tsv > edges_sorted.tsv
sort -k1,1 id_grade.tsv > id_grade_sorted.tsv
join -t $'\t' -1 2 -2 1 edges_sorted.tsv id_grade_sorted.tsv > joined.tsv
cut -f2,3 joined.tsv > left_outcome.tsv
head -5 left_outcome.tsv
sort -k1,1 left_outcome.tsv -o left_outcome.tsv
datamash -s -g 1 count 2 mean 2 median 2 < left_outcome.tsv > cluster_outcomes.tsv
sed "s/'//g; s/\"//g; s/\r//g; s/ //g" left_outcome.tsv > left_outcome_clean.tsv
head -5 left_outcome_clean.tsv
sort -k1,1 left_outcome_clean.tsv -o left_outcome_clean.tsv
datamash -s -g 1 count 2 mean 2 median 2 < left_outcome_clean.tsv > cluster_outcomes.tsv
column -t cluster_outcomes.tsv | head
