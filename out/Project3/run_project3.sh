{\rtf1\ansi\ansicpg1252\cocoartf2821
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\froman\fcharset0 TimesNewRomanPSMT;\f1\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;\red0\green0\blue0;\red1\green22\blue40;\red0\green0\blue0;
}
{\*\expandedcolortbl;;\cssrgb\c0\c0\c0;\cssrgb\c0\c11373\c20784;\csgray\c0\c0;
}
\margl1440\margr1440\vieww12480\viewh9000\viewkind0
\deftab720
\pard\pardeftab720\sl368\sa213\partightenfactor0

\f0\fs32 \cf2 \expnd0\expndtw0\kerning0
header=$(head -n 1 student_performance.csv)\
\pard\pardeftab720\sl368\partightenfactor0
\cf2 col1_index=$(echo "$header" | awk -F ',' '\{for(i=1;i<=NF;i++) \{if($i=="Attendance") print i\}\}')
\fs24  \
\

\fs32 col2_index=$(echo "$header" | awk -F ',' '\{for(i=1;i<=NF;i++) \{if($i=="Motivation") print i\}\}')
\fs24  \
\

\fs32 awk -F ',' -v c1="$col1_index" -v c2="$col2_index" '\{print $c1 "\\t" $c2 | "(head -n 1 && tail -n +2 | sort -n -k 1)"\}' student_performance.csv\'a0 > edges.tsv
\fs24  \
\
\pard\pardeftab720\sl368\sa213\partightenfactor0

\fs32 \cf2 (echo -n\'a0 -e "Count\\t" | cat - <( head -n 1 edges.tsv | cut -f 1); tail -n +2 edges.tsv | cut -f 1 | uniq -c) > entity_counts.tsv\
string=$(tail -n +2 entity_counts.tsv\'a0 | awk '$1 >= 350 \{print $2\}')\
\pard\pardeftab720\sl368\partightenfactor0
\cf2 array=($string)
\fs24  
\fs32 \
\
\pard\pardeftab720\sl368\sa213\partightenfactor0
\cf2 head -n 1 edges.tsv > edges_thresholded.tsv\
awk -F '\\t' -v a="$string" 'BEGIN \{split(a, array, " ");\}\
\{\
\'a0\'a0\'a0 flag = 0; \
\'a0\'a0\'a0 for (num in array)\
\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \{\
\'a0\'a0\'a0\'a0\'a0\'a0 \'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0if (array[num] == $1)\
\pard\pardeftab720\li960\fi960\sl368\sa213\partightenfactor0
\cf2 \'a0\{\
\pard\pardeftab720\sl368\sa213\partightenfactor0
\cf2 \'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0flag = 1;\
\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0break;\
\'a0\'a0\'a0\'a0\'a0\'a0 \'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0\}\
\'a0\'a0\'a0 \'a0\'a0\'a0\'a0\'a0\'a0\'a0 \}\
\'a0\'a0\'a0 \'a0\'a0\'a0\'a0\'a0\'a0\'a0 if (flag == 1)\
\pard\pardeftab720\fi960\sl368\sa213\partightenfactor0
\cf2 \{\
\pard\pardeftab720\sl368\sa213\partightenfactor0
\cf2 \'a0\'a0\'a0\'a0\'a0\'a0\'a0 \'a0\'a0 print $0;\
\pard\pardeftab720\fi960\sl368\sa213\partightenfactor0
\cf2 \}\
\pard\pardeftab720\sl368\partightenfactor0
\cf2 \}' edges.tsv >> edges_thresholded.tsv
\fs24  \
\
\pard\pardeftab720\sl322\partightenfactor0

\fs32 \cf3 awk '($N1 + 0) >= 350 \{print\}' entity_counts.tsv > cluster_sizes.tsv\cf2 \
\
\pard\pardeftab720\partightenfactor0
\cf2 \cb4 sort -t$'\\t' -k2 -nr entity_counts.tsv | head -30 > top30_counts.txt\
ls -l ~/Downloads/top30_counts.txt\
head -10 top30_counts.txt\
awk -F'\\t' -v count="$COUNTS" '$1 == count' top30_counts.txt > top30_counts.tsv\
sort -t$'\\t' -k2 -nr entity_counts.tsv | head -30 > top30_counts.tsv\
ls -lh top30_counts.tsv\
head -5 top30_counts.tsv\
\
edges_thresholded.tsv > cluster_edges.tsv\
head cluster_edges.tsv\
wc -l cluster_edges.tsv\
tail -n +2 student_performance.tsv | nl -w1 -s$'\\t' > student_performance_indexed.tsv\
head -3 student_performance_indexed.tsv\
cut -f1,17 student_performance_indexed.tsv > id_grade.tsv\
head id_grade.tsv\
sort -k2,2 edges_thresholded.tsv > edges_sorted.tsv\
sort -k1,1 id_grade.tsv > id_grade_sorted.tsv\
join -t $'\\t' -1 2 -2 1 edges_sorted.tsv id_grade_sorted.tsv > joined.tsv\
cut -f2,3 joined.tsv > left_outcome.tsv\
head -5 left_outcome.tsv\
sort -k1,1 left_outcome.tsv -o left_outcome.tsv\
datamash -s -g 1 count 2 mean 2 median 2 < left_outcome.tsv > cluster_outcomes.tsv\
sed "s/'//g; s/\\"//g; s/\\r//g; s/ //g" left_outcome.tsv > left_outcome_clean.tsv\
head -5 left_outcome_clean.tsv\
sort -k1,1 left_outcome_clean.tsv -o left_outcome_clean.tsv\
datamash -s -g 1 count 2 mean 2 median 2 < left_outcome_clean.tsv > cluster_outcomes.tsv\
column -t cluster_outcomes.tsv | head
\f1 \cf2 \cb1 \
}