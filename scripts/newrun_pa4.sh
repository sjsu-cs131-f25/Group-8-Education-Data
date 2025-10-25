#!/usr/bin/env bash
# run_pa4.sh
# PA4 entry script (SED + AWK + shell) - implements steps 1,2,3
# Usage: ./run_pa4.sh <INPUT>
# Produces: out/ and logs/ (tab-separated .tsv outputs)
#
# Requirements: sed, awk, cut, sort, uniq, head, tail, tee, wc
set -euo pipefail

########################################
# Helpers & environment
########################################
me="$(basename "$0")"
if [ "${#}" -ne 1 ]; then
  echo "Usage: $me <INPUT CSV/TSV>" >&2
  exit 2
fi

INPUT="$1"
OUTDIR="../out"
LOGDIR="../logs"
TMPDIR="$(mktemp -d)"
CLEANED="${TMPDIR}/cleaned.tsv"
BEFORE_SAMPLE="${OUTDIR}/before_sample.tsv"
AFTER_SAMPLE="${OUTDIR}/after_sample.tsv"
HEADER_FILE="${TMPDIR}/header.tsv"
DETECTED_DELIM=""
NUM_COLS=0

mkdir -p "$OUTDIR" "$LOGDIR"
exec 3>"$LOGDIR/run_pa4.log"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ:)] START $me" >&3

# Basic permission / existence checks
if [ ! -e "$INPUT" ]; then
  echo "ERROR: input '$INPUT' does not exist." | tee >(cat >&3) >&2
  exit 3
fi
if [ ! -r "$INPUT" ]; then
  echo "Attempting to set group+read permission on $INPUT" | tee >(cat >&3)
  chmod -R g+rX "$INPUT" || true
fi

########################################
# 1) Detect delimiter (tab or comma) and take a small before-sample
########################################
# Check for presence of tab characters in first 5 lines
if head -n 5 "$INPUT" | grep -q $'\t'; then
  DETECTED_DELIM=$'\t'
  echo "Detected delimiter: TAB" >&3
else
  DETECTED_DELIM=","
  echo "Detected delimiter: COMMA (defaulting to CSV)" >&3
fi

# produce a small before sample (verbatim)
head -n 20 "$INPUT" > "${TMPDIR}/_raw_head20"
# Save human-friendly before sample (tab-separated if CSV converted below)
cp "${TMPDIR}/_raw_head20" "$BEFORE_SAMPLE"
echo "Wrote before-sample -> $BEFORE_SAMPLE" >&3

########################################
# 2) Clean & normalize (SED + light awk)
#    Goals:
#      - remove CR (\r), remove BOM
#      - normalize smart quotes/brackets to plain
#      - collapse multiple internal whitespace
#      - convert delimiter to TAB
#      - strip leading/trailing whitespace around fields
#      - normalize NA/empty to "NA"
#      - remove thousands separators in numeric-looking tokens (e.g., 1,234 -> 1234)
#      - ensure token counts per row consistent (we'll mark inconsistent rows)
########################################

# Step A: line-level sed normalizations
# - Remove CR, BOM
# - Normalize smart quotes “ ” ‘ ’ to " and '
# - Strip square and curly brackets characters and repeated punctuation
# - Collapse internal repeated spaces (we'll finalize trimming field-level in awk)
sed -E $'
s/\r//g
s/^\xEF\xBB\xBF//   
s/[“”„”]/"/g
s/[‘’‚]/'\''/g
s/[\[\]\{\}]//g
s/[[:space:]]{2,}/ /g
' "$INPUT" > "${TMPDIR}/_sed_stage1" 

# Step B: convert delimiter to TAB if CSV
if [ "$DETECTED_DELIM" = "," ]; then
  # A conservative CSV->TSV converter:
  # - This naive converter assumes there are no embedded newlines in fields.
  # - It will convert commas to tabs, preserving simple quoted fields by removing wrapping quotes.
  awk '
  BEGIN { FS=","; OFS="\t" }
  {
    # remove leading/trailing whitespace for the full line
    gsub(/^[ \t]+|[ \t]+$/, "", $0)
    # remove surrounding quotes around each field if present and trim
    for(i=1;i<=NF;i++){
      f=$i
      # remove leading/trailing space
      gsub(/^[ \t]+|[ \t]+$/, "", f)
      # remove leading/trailing quotes
      if (f ~ /^".*"$/ || f ~ /^'\''.*'\''$/) {
        sub(/^"/,"",f); sub(/"$/,"",f)
        sub(/^'\''/,"",f); sub(/'\''$/,"",f)
      }
      # collapse internal multi-space to single space
      gsub(/[[:space:]]+/, " ", f)
      # output cleaned field
      printf "%s", f
      if (i<NF) printf "\t"
    }
    printf "\n"
  }' "${TMPDIR}/_sed_stage1" > "${TMPDIR}/_tsv_candidate"
else
  # Already tab-separated: just normalize whitespace around fields in awk
  awk '
  BEGIN { FS="\t"; OFS="\t" }
  {
    for(i=1;i<=NF;i++){
      f=$i
      gsub(/^[ \t]+|[ \t]+$/, "", f)
      gsub(/[[:space:]]+/, " ", f)
      printf "%s", f
      if(i<NF) printf OFS
    }
    printf "\n"
  }' "${TMPDIR}/_sed_stage1" > "${TMPDIR}/_tsv_candidate"
fi

# Step C: numeric cleanups & NA normalization (awk)
# - Remove thousands separators (commas inside numbers)
# - Normalizes blank fields to NA
# - Save header separately
awk -F'\t' -v OFS='\t' '
NR==1 {
  header=$0
  print header > "'"${HEADER_FILE}"'"
  # count columns
  ncols = NF
  print header
  next
}
{
  # ensure we have exactly ncols fields by padding with NA if missing
  if (NF < ncols) {
    for(i=NF+1;i<=ncols;i++) $i="NA"
  }
  # if NF > ncols, keep first ncols fields (simple truncation)
  if (NF > ncols) {
    # do nothing special here: awk will still have fields > ncols, but we print only 1..ncols below
  }
  for(i=1;i<=ncols;i++){
    f=$i
    # trim
    gsub(/^[ \t]+|[ \t]+$/,"",f)
    # collapse internal whitespace
    gsub(/[[:space:]]+/, " ", f)
    # remove thousands separators in numeric-looking tokens (e.g., 1,234 -> 1234)
    if (f ~ /^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$/) {
      gsub(/,/,"",f)
    }
    # normalize empty to NA
    if (f=="" || f=="-" || f=="NULL" || f=="null") f="NA"
    $i = f
  }
  # print only first ncols fields to keep consistent token count
  out = $1
  for(i=2;i<=ncols;i++) out = out OFS $i
  print out
}
' "${TMPDIR}/_tsv_candidate" > "$CLEANED"

# record number of columns
NUM_COLS=$(head -n1 "$HEADER_FILE" | awk -F'\t' '{print NF}')
echo "Header columns detected: $NUM_COLS" >&3

# produce a small after sample
head -n 20 "$CLEANED" > "$AFTER_SAMPLE"
echo "Wrote after-sample -> $AFTER_SAMPLE" >&3

########################################
# 3) Skinny tables & frequency tables (UNIX EDA)
#    - auto-detect candidate categorical columns (low- to medium-cardinality)
#    - produce at least two freq tables, a Top-N list, and a skinny subset
########################################

# Utility: list column unique counts
# output: col_index<TAB>col_name<TAB>unique_count
awk -F'\t' -v OFS='\t' -v tmp="$TMPDIR" -v cleaned="$CLEANED" '
NR==1 {
  for(i=1;i<=NF;i++) {
    colnames[i]=$i
  }
  next
}
{
  for(i=1;i<=NF;i++){
    # build keys as col_i|value (to count uniques)
    key = i SUBSEP $i
    seen[key]=1
  }
}
END {
  # count uniques per column
  for (k in seen) {
    split(k, parts, SUBSEP)
    col=parts[1]+0
    colcount[col]++
  }
  for (i=1;i<=length(colnames);i++) {
    if (!(i in colcount)) colcount[i]=0
    print i, colnames[i], colcount[i]
  }
}
' "$CLEANED" | sort -k3,3n > "${TMPDIR}/col_cardinality.tsv"

# pick 2 categorical-ish columns: unique count >=2 and <= 200 (tunable)
C1_INFO=$(awk -F'\t' '$3>=2 && $3<=200 {print $0}' "${TMPDIR}/col_cardinality.tsv" | head -n1 || true)
C2_INFO=$(awk -F'\t' '$3>=2 && $3<=200 {print $0}' "${TMPDIR}/col_cardinality.tsv" | sed -n '2p' || true)

# fallback: if not found, pick columns 1 and 2
if [ -z "$C1_INFO" ]; then
  C1_INFO=$(awk -F'\t' 'NR==1{print $0}' "${TMPDIR}/col_cardinality.tsv")
fi
if [ -z "$C2_INFO" ]; then
  C2_INFO=$(awk -F'\t' 'NR==2{print $0}' "${TMPDIR}/col_cardinality.tsv")
fi

# parse indexes & names
C1_IDX=$(echo "$C1_INFO" | awk -F'\t' '{print $1}')
C1_NAME=$(echo "$C1_INFO" | awk -F'\t' '{print $2}')
C2_IDX=$(echo "$C2_INFO" | awk -F'\t' '{print $1}')
C2_NAME=$(echo "$C2_INFO" | awk -F'\t' '{print $2}')

echo "Selected categorical columns for freq analysis: $C1_IDX:$C1_NAME and $C2_IDX:$C2_NAME" >&3

# Frequency table for C1
# Header -> colname \t count
awk -v FS='\t' -v col="$C1_IDX" -v name="$C1_NAME" '
NR>1 { counts[$col]++ }
END {
  print name "\tcount"
  for (v in counts) print v "\t" counts[v]
}
' "$CLEANED" | sort -k2,2nr -k1,1 > "${OUTDIR}/freq_${C1_NAME}.tsv"

# Frequency table for C2
awk -v FS='\t' -v col="$C2_IDX" -v name="$C2_NAME" '
NR>1 { counts[$col]++ }
END {
  print name "\tcount"
  for (v in counts) print v "\t" counts[v]
}
' "$CLEANED" | sort -k2,2nr -k1,1 > "${OUTDIR}/freq_${C2_NAME}.tsv"

echo "Wrote frequency tables: ${OUTDIR}/freq_${C1_NAME}.tsv , ${OUTDIR}/freq_${C2_NAME}.tsv" >&3

# Top-N list (Top 10 values of C1)
(head -n1 "${OUTDIR}/freq_${C1_NAME}.tsv" && tail -n +2 "${OUTDIR}/freq_${C1_NAME}.tsv" | head -n 10) \
  > "${OUTDIR}/top10_${C1_NAME}.tsv"

# Skinny table: select the header + the two categorical columns and first numeric-looking column (if any)
# Find first numeric-like column by header name heuristics (score|grade|mark|avg) or by content test
NUM_IDX=$(awk -F'\t' '
BEGIN { IGNORECASE=1 }
NR==1 {
  for (i=1;i<=NF;i++) {
    h=tolower($i)
    if (h ~ /score|grade|mark|avg|percent|percentile|gpa/) {
      print i
      exit
    }
  }
}' "${HEADER_FILE}" || true)

# If not found, detect by sampling the second row for numeric token
if [ -z "$NUM_IDX" ]; then
  NUM_IDX=$(awk -F'\t' 'NR==2 {
    for(i=1;i<=NF;i++) {
      if ($i ~ /^-?[0-9]+(\.[0-9]+)?$/) { print i; exit }
    }
  }' "$CLEANED" || true)
fi

# fallback: choose column 3 if still empty and exists
if [ -z "$NUM_IDX" ]; then
  if [ "$NUM_COLS" -ge 3 ]; then
    NUM_IDX=3
  else
    NUM_IDX=1
  fi
fi

# write skinny table header and data (deterministic sort)
awk -v FS='\t' -v OFS='\t' -v c1="$C1_IDX" -v c2="$C2_IDX" -v n="$NUM_IDX" '
NR==1 { print "col_" c1 "_" NR, "col_" c2 "_" NR, "num_col_" n "_" NR; next }
{ print $c1, $c2, $n }
' "$CLEANED" > "${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv"
# deterministic sort by first two cols
(head -n1 "${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv" && tail -n +2 "${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv" | sort -t$'\t' -k1,1 -k2,2) > "${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv.tmp" && mv "${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv.tmp" "${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv"

echo "Wrote skinny table -> ${OUTDIR}/skinny_${C1_NAME}_${C2_NAME}.tsv" >&3
echo "Wrote Top-10 -> ${OUTDIR}/top10_${C1_NAME}.tsv" >&3

########################################
# 4) Quality filters (AWK) - enforce simple business rules:
#    - keep header
#    - keep rows where first column (assumed key) is not NA
#    - keep rows that have exactly expected number of tokens
#    - drop rows where any numeric field is negative
#    - write filtered TSV and log dropped rows counts
########################################
FILTERED="${OUTDIR}/filtered.tsv"
REJECTED="${OUTDIR}/rejected_rows.tsv"

awk -v FS='\t' -v OFS='\t' -v ncols="$NUM_COLS" '
NR==1 { print; next }
{
  # check token count
  if (NF != ncols) { print $0 > "'"${REJECTED}"'"; bad_tokens++; next }
  # check primary key (first field) not NA
  if ($1 == "NA" || $1 == "") { print $0 > "'"${REJECTED}"'"; bad_key++; next }
  # check numeric fields not negative: test every field that looks numeric
  badnum=0
  for(i=1;i<=NF;i++){
    if ($i ~ /^-?[0-9]+(\.[0-9]+)?$/) {
      if ($i+0 < 0) { badnum=1; break }
    }
  }
  if (badnum) { print $0 > "'"${REJECTED}"'"; bad_num++; next }
  # passed all filters
  print
  kept++
}
END {
  printf("kept=%d\nbad_tokens=%d\nbad_key=%d\nbad_num=%d\n",kept+0,bad_tokens+0,bad_key+0,bad_num+0) > "/dev/stderr"
}
' "$CLEANED" > "$FILTERED" 2> "$LOGDIR/filter_stats.log"

# deterministic sort filtered by first column then second
(head -n1 "$FILTERED" && tail -n +2 "$FILTERED" | sort -t$'\t' -k1,1 -k2,2) > "${OUTDIR}/filtered.sorted.tsv"
mv "${OUTDIR}/filtered.sorted.tsv" "$FILTERED"

echo "Wrote filtered rows -> $FILTERED" >&3
echo "Rejected rows put in -> ${REJECTED} (if any)" >&3
echo "Filter stats logged to -> $LOGDIR/filter_stats.log" >&3








#####################################################
# 5. Ratios, buckets and per-entity summaries(AWK)
# Compute at least one ratio
# Guard against division by zero
# a per-entity summary(count,avg,optionally min/max) using printf formatting
# Convert numeric fields to readable categories using FILTERED dataset
##########################################################################

### 5A  Derived ratios
## Define the output path in one pass
RATIOS="${OUTDIR}/with_ratios.tsv"
CATEGORIZED="${OUTDIR}/categorized_data.tsv"



awk -F'\t' -v OFS='\t' \
  -v RATIOS="$RATIOS" -v CATEGORIZED="$CATEGORIZED" '

# Helper functions
function num(v,   s) {
  # force string
  s = v""                           
  if (s=="" || s=="NA" || s=="NaN" || s=="NULL") return "NA"
  return v+0
}


function safe_div(n, d,   dn) {
   if (d=="" || d=="NA") return "NA"
   dn = d+0
   if (dn==0) return "NA"
   return (n+0)/dn

}
NR==1{
      # Build header map 
       for(i=1;i<=NF;i++) h[$i]=i

       # Output for ratios (original + ratios)
       print $0, "StudyEfficiency", "StressToMotivation", "EngagementRatio"
       
       # Output for categorized data (original + categories)
       print $0, "FinalLetter", "ExamBand", "GenderLabel", "InternetLabel", "MotivationLevel" > "'"${CATEGORIZED}"'"
       next
       
       }

  {
   # Pull fields for ratios
    sg = num($(h["StudyHours"]))
    fg = num($(h["FinalGrade"]))
    st = num($(h["StressLevel"]))
    mt = num($(h["Motivation"]))
    rs = num($(h["Resources"]))
    dc = num($(h["Discussions"]))
    oc = num($(h["OnlineCourses"])) 
  
   # Ratios(guarded)
   ## set StudyEfficiency=FinalGrade/StudyHours. If StudyHours==0,set"NA"
   if (sg=="NA" || sg<=0) se="NA"; else se=safe_div(fg, sg)
      
   # mt == -1  -> mt+1 == 0  -> NA
   if (mt=="NA" || (mt+0)==-1) sm="NA"; else sm=safe_div(st, (mt+0)+1)

   # rs == -1  -> rs+1 == 0  -> NA
   if (rs=="NA" || (rs+0)==-1) {
    eg="NA"
  } else {
    sumDO = (dc=="NA"?0:dc) + (oc=="NA"?0:oc)
    eg = safe_div(sumDO, (rs+0)+1)
  } 

    # Format ratios
    if (se != "NA") se = sprintf("%.4f", se)
    if (sm != "NA") sm = sprintf("%.4f", sm)
    if (eg != "NA") eg = sprintf("%.4f", eg)

    # Write ratios output
    print $0, se, sm, eg


    # Category conversions for categorized output
    final_grade = ($(h["FinalGrade"]) == "NA" ? "NA" : $(h["FinalGrade"]))
    exam_score = ($(h["ExamScore"]) == "NA" ? "NA" : $(h["ExamScore"]))
    gender = ($(h["Gender"]) == "NA" ? "NA" : $(h["Gender"]))
    internet = ($(h["Internet"]) == "NA" ? "NA" : $(h["Internet"]))
    motivation = ($(h["Motivation"]) == "NA" ? "NA" : $(h["Motivation"]))


    # Convert to categories
    g = final_grade + 0
    if (g == 3) letter = "A"
    else if (g == 2) letter = "B" 
    else if (g == 1) letter = "C"
    else if (g == 0) letter = "D"
    else letter = "F"



    s = exam_score + 0
    if (s < 50) band = "LOW"
    else if (s < 75) band = "MID"
    else band = "HIGH"

    
    gen = gender + 0
    if (gen == 1) genlabel = "Female"
    else genlabel = "Male"

    
    net = internet + 0
    if (net == 1) netlabel = "Yes"
    else netlabel = "No"

    
    m = motivation + 0
    if (m == 0) motlevel = "None"
    else if (m == 1) motlevel = "Low"
    else if (m == 2) motlevel = "Medium"
    else motlevel = "High" 

    # Write categorized data
    print $0, letter, band, genlabel, netlabel, motlevel > "'"${CATEGORIZED}"'"
}

' "$FILTERED" > "$RATIOS"

echo "Wrote ratios -> $RATIOS" >&3
echo "Wrote categorized data -> $CATEGORIZED" >&3

 

### 5B Continue with your existing buckets code

## Define output path
 BUCKETS="${OUTDIR}/with_buckets.tsv"

#### Convert the numeric value to ZERO,LO,MID,HI, but keep "NA" as "NA" use function bucket

awk -F'\t' -v OFS='\t' '
function bucket(x, v){
   if(x=="NA"|| x=="") return "NA"
   v = x + 0
   if(v<=0) return "ZERO"
   else if (v<50) return "LO"
   else if (v<75) return "MID"
   else return "HI"
}


### build header map and print the original header with two new bucket column names

NR==1{
  for(i=1;i<=NF;i++) h[$i]=i
  print $0, "ExamScoreBucket","FinalGradeBucket"
  next
}

{
  ##  Get ExamScore value and FinalGrade value
  es = h["ExamScore"] ? $(h["ExamScore"]) : "NA"
  fg = h["FinalGrade"] ? $(h["FinalGrade"]) : "NA"

  ## Convert empty strings to "NA"
  if (es == "") es = "NA"
  if (fg == "") fg = "NA"
  print $0, bucket(es), bucket(fg)
}

' "$FILTERED" > "$BUCKETS"



##### Bucket Frequencies
##### Count occurrences of each ExamScoreBucket (1st new column)
##### Count occurrences of each FinalGradeBucket (2nd new column)
awk -F'\t' '
NR==1 { next }
{ exam[$1]++; final[$2]++ }
END {
  print "bucket\ttype\tcount";
  for (b in exam)  printf "%s\texam\t%d\n",  b, exam[b];
  for (b in final) printf "%s\tfinal\t%d\n", b, final[b];
}
   ## Process buckets file sort  by column2("exam" or "final") and column1 (bucket name)
' "$BUCKETS" | sort -t$'\t' -k2,2 -k1,1 > "${OUTDIR}/bucket_counts.tsv"

echo "Wrote -> $BUCKETS and ${OUTDIR}/bucket_counts.tsv" >&3


########################################
# 5C. Per-entity summary (Gender) — count & averages
########################################

### set output path as for gender summary

SUMMARY="${OUTDIR}/summary_by_gender.tsv"

awk -F'\t' -v OFS='\t' '
NR==1 {
  # header map
  for (i=1; i<=NF; i++) h[$i]=i
  idxG  = (("Gender"     in h) ? h["Gender"]     : 0)
  idxES = (("ExamScore"  in h) ? h["ExamScore"]  : 0)
  idxFG = (("FinalGrade" in h) ? h["FinalGrade"] : 0)
  next
}

{
  ### Skip if no GenderLabel column
  #### Get gender value
  ##### Normalize empty and space to "NA"
  if (idxG==0) next
  g = $idxG
  if (g=="" || g==" ") g="NA"


  #### Count rows per gender
  cnt[g]++

 
  # If ExamScore and FinalGrade columns exist and value is valid, add to sum and count
  if (idxES>0) {
    es = $idxES
    if (es!="" && es!="NA") { es+=0; sum_es[g]+=es; n_es[g]++ }
  }
  if (idxFG>0) {
    fg = $idxFG
    if (fg!="" && fg!="NA") { fg+=0; sum_fg[g]+=fg; n_fg[g]++ }
  }
}

 ### Print header with calculation of average ExamScore and FinalGrade(with guarded) and print formatted row 
END {
  print "Gender","Count","AvgExam","AvgFinal"
  for (g in cnt) {
    ae = ((g in n_es) && n_es[g]>0) ? sprintf("%.2f", sum_es[g]/n_es[g]) : "NA"
    af = ((g in n_fg) && n_fg[g]>0) ? sprintf("%.2f", sum_fg[g]/n_fg[g]) : "NA"
    printf "%s\t%d\t%s\t%s\n", g, cnt[g]+0, ae, af
  }
}
' "$FILTERED" | { read -r hdr; echo "$hdr"; sort -t$'\t' -k1,1; } > "$SUMMARY"

echo "Wrote per-entity summary by gender -> $SUMMARY" >&3





##### Summary by Learning Style 


### Define output path as for learning style summary

SUMMARY_LS="${OUTDIR}/summary_by_learningstyle.tsv"



### Create header map and get LearningStyle, ExamScore, and FinalGrade values
##### Normalized empty values to "NA"
awk -F'\t' -v OFS='\t' '
NR==1{
  for(i=1;i<=NF;i++) 
  h[$i]=i
  next
}
{
  s = $(h["LearningStyle"]); if (s=="" || s==" ") s="NA"
  es = $(h["ExamScore"]);  fg = $(h["FinalGrade"])

#### Count occurrences of each LearningStyle value
  cnt[s]++

### Only process valid of ExamScore and FinalGrade values
##### convert to number, add to sum, and increment count for LearningStyle
  if (es!="" && es!="NA"){ es+=0; sum_es[s]+=es; n_es[s]++ }
  if (fg!="" && fg!="NA"){ fg+=0; sum_fg[s]+=fg; n_fg[s]++ }
}
END{
  print "LearningStyle","Count","AvgExam","AvgFinal"

  ### Loop each LearningSyle by calculating average of ExamScore and FinalGrade("NA" if no data)
  for (k in cnt){
    printf "%s\t%d\t", k, cnt[k]

    ## Check if we have exam scores for this LearningStyle
    if (n_es[k] > 0) {
        printf "%.2f\t", sum_es[k]/n_es[k]
    } else {
      ### If no data, print "NA" + tab
        printf "NA\t"
    }

    ##### Check if we have final grades for this LearningStyle
    ######## If yes, print average with 2 decimal places + newline, if no data print "NA" + newline
    if (n_fg[k] > 0) {
        printf "%.2f\n", sum_fg[k]/n_fg[k]
    } else {
        printf "NA\n"
    }
  }
}
' "$FILTERED" | sort -t$'\t' -k1,1 > "$SUMMARY_LS"
echo "Wrote learning style -> $SUMMARY_LS" >&3




########################################
# 6) String structure analysis
#  Extract ID prefixes and aggregate
#  Parse code patterns and profile distributions  
#  Normalize case-folded keys for duplicate detection
#  Compute length buckets and frequency analysis
########################################


### 6A) Extract ID prefixes and aggregate

### Define output path 

PREFIX_ANALYSIS="${OUTDIR}/prefix_analysis.tsv"


awk -F'\t' -v OFS='\t' '
NR==1 {
    for(i=1;i<=NF;i++)
        if($i ~ /LearningStyle|GenderLabel|MotivationLevel/) cols[i]=$i
    next
}
NR>1 {
    for(i in cols) {
        if($i != "" && $i != "NA" && length($i) >= 3) {
            prefix = substr($i, 1, 3)
            print cols[i], prefix, $i
        }
    }
}' "$CATEGORIZED" \
| sort -t$'\t' -k1,1 -k2,2 \
| awk -F'\t' -v OFS='\t' '
BEGIN { print "column","prefix","count","percentage","example_value","unique_values" }

# new group → flush previous
$1!=prev_col || $2!=prev_prefix {
  if (prev_col!="") {
    pct = (col_total[prev_col] > 0) ? (count/col_total[prev_col])*100 : 0
    printf "%s\t%s\t%d\t%.2f\t%s\t%d\n", prev_col, prev_prefix, count, pct, example, unique_count
  }
  prev_col=$1; prev_prefix=$2
  count=0; unique_count=0; delete seen; example=$3
}

# tally this row
{
  count++
  if (!seen[$3]) { seen[$3]=1; unique_count++ }
  col_total[$1]++
}

END {
  if (prev_col!="") {
    pct = (col_total[prev_col] > 0) ? (count/col_total[prev_col])*100 : 0
    printf "%s\t%s\t%d\t%.2f\t%s\t%d\n", prev_col, prev_prefix, count, pct, example, unique_count
  }
}' > "$PREFIX_ANALYSIS"

echo "Wrote prefix analysis -> $PREFIX_ANALYSIS" >&3


### 6B) Parse code patterns and profile distributions

CODE_PATTERNS="${OUTDIR}/code_patterns.tsv"

# Parse categorical values as "codes" and classify patterns
awk -F'\t' -v OFS='\t' '
function parse_code_pattern(value) {
    if(value == "" || value == "NA") return "MISSING"
    
    # function to classify string pattern
    if(value ~ /^[A-Z][a-z]+$/) return "Capitalized_Word"
    if(value ~ /^[a-z]+$/) return "Lowercase_Word" 
    if(value ~ /^[A-Z]+$/) return "Uppercase_Word"
    if(value ~ /^[A-Z][a-z]+\s+[A-Z][a-z]+$/) return "Two_Capitalized_Words"
    if(value ~ /^[0-9]+$/) return "Numeric_Code"
    if(value ~ /^[A-Za-z]+[0-9]+$/) return "AlphaNumeric_Suffix"
    if(value ~ /^[0-9]+[A-Za-z]+$/) return "NumericAlpha_Prefix"
    if(value ~ /^[A-Z]-[0-9]/) return "Letter_Dash_Number"
    if(value ~ / /) return "Multi_Word"
    
    return "Complex_Pattern"
}

NR==1 {
    print "column", "code_pattern", "count", "percentage", "example_value"
    for(i=1;i<=NF;i++) 
        if($i ~ /LearningStyle|GenderLabel|FinalLetter|ExamBand|MotivationLevel/) 
            cols[i]=$i
    total_rows = 0
}

### header process to identify columns to analyze and initialize counter
NR>1 {
    total_rows++
    for(i in cols) {
        if($i != "" && $i != "NA") {
            pattern = parse_code_pattern($i)
            key = cols[i] "|" pattern
            count[key]++
            if(!example[key]) example[key] = $i
        }
    }
}

END {
    for(key in count) {
        split(key, parts, "|")
        percentage = (count[key] / total_rows) * 100
        printf "%s\t%s\t%d\t%.1f%%\t%s\n", parts[1], parts[2], count[key], percentage, example[key]
    }
}' "$CATEGORIZED" | \
sort -t$'\t' -k1,1 -k3,3nr > "$CODE_PATTERNS"

echo "Wrote code patterns -> $CODE_PATTERNS" >&3

### 6C) Normalize case-folded keys for duplicate detection
CASE_CLUSTERS="${OUTDIR}/case_clusters.tsv"

# Extract, normalize, and find case variations
awk -F'\t' -v OFS='\t' '
NR==1 {
    for(i=1;i<=NF;i++) 
        if($i ~ /LearningStyle|Gender|Motivation/) 
            cols[i]=$i
}
NR>1 {
    for(i in cols) 
        if($i != "" && $i != "NA") 
            print cols[i], $i
}' "$CATEGORIZED" | \

# Normalize to lowercase and trim
awk -F'\t' -v OFS='\t' '{
    normalized = tolower($2)
    gsub(/[[:space:]]+/, " ", normalized)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", normalized)
    print $1, $2, normalized
}' | \

# Identify case variations (different original cases for same normalized form)
sort -t$'\t' -k1,1 -k3,3 -k2,2 | \
awk -F'\t' -v OFS='\t' '
BEGIN {print "column", "normalized_value", "original_variations", "variation_count", "total_occurrences", "example_original"}
$1 != prev_col || $3 != prev_norm {
    if(prev_col != "") {
        variations = ""
        for(v in seen) variations = (variations == "" ? v : variations "|" v)
        print prev_col, prev_norm, variations, variation_count, total_count, example_original
    }
    prev_col = $1
    prev_norm = $3
    total_count = 0
    variation_count = 0
    delete seen
    example_original = $2
}
{
    total_count++
    if(!seen[$2]) {
        seen[$2] = 1
        variation_count++
    }
}
END {
    if(prev_col != "") {
        variations = ""
        for(v in seen) variations = (variations == "" ? v : variations "|" v)
        print prev_col, prev_norm, variations, variation_count, total_count, example_original
    }
}' | \
awk -F'\t' '$4 > 1' | \
sort -t$'\t' -k1,1 -k4,4nr > "$CASE_CLUSTERS"

echo "Wrote case clusters -> $CASE_CLUSTERS" >&3

### 6D) Compute length buckets and frequency analysis
LENGTH_FREQUENCY="${OUTDIR}/length_frequency.tsv"

# Extract values and compute length distributions
awk -F'\t' -v OFS='\t' '
NR==1 {
    for(i=1;i<=NF;i++) 
        h[$i]=i  
        if($i ~ /LearningStyle|GenderLabel|FinalLetter|ExamBand|MotivationLevel/) 
            cols[i]=$i
}
NR>1 {
    for(i in cols) 
        if($i != "" && $i != "NA") 
            print cols[i], $i, length($i)
}' "$CATEGORIZED" | \

# Categorize into length buckets
awk -F'\t' -v OFS='\t' '{
    len = $3
    #### single character values
    if(len == 1) bucket = "1_char"
    ### 1-3 characters
    else if(len <= 3) bucket = "short_1-3"
    ### 4-6 characters
    else if(len <= 6) bucket = "medium_4-6"
    ### 7-9 characters 
    else if(len <= 9) bucket = "long_7-9"
    ### 10-12 characters
    else if(len <= 12) bucket = "xlong_10-12"
    ### over 13 characters
    else bucket = "extreme_13+"
    print $1, $2, bucket, len
}' | \

# Aggregate frequency statistics
sort -t$'\t' -k1,1 -k3,3 | \
awk -F'\t' -v OFS='\t' '
BEGIN {print "column", "length_bucket", "count", "percentage", "avg_length", "min_length", "max_length", "example_value"}
$1 != prev_col || $3 != prev_bucket {
    if(prev_col != "") {
        percentage = (count / total_col_count[prev_col]) * 100
        print prev_col, prev_bucket, count, percentage, total_len/count, min_len, max_len, example
    }
    prev_col = $1
    prev_bucket = $3
    count = 0
    total_len = 0
    min_len = 999
    max_len = 0
    example = $2
    total_col_count[prev_col] += 0
}
{
    count++
    total_len += $4
    total_col_count[$1] += 1
    if($4 < min_len) min_len = $4
    if($4 > max_len) max_len = $4
}
END {
    if(prev_col != "") {
        percentage = (count / total_col_count[prev_col]) * 100
        print prev_col, prev_bucket, count, percentage, total_len/count, min_len, max_len, example
    }
}' > "$LENGTH_FREQUENCY"

echo "Wrote length frequency -> $LENGTH_FREQUENCY" >&3




####################################################################
# 7) Signal discovery - Numeric signals for education dataset
#    - Distribution profiles (mean, std, min, max)
#    - Outlier flags via z-scores (AWK + sort)
#    - Category-wise comparisons of averages
#    - Ranked "signals" table
####################################################################

### 7A) Distribution profiles for all numeric columns

NUMERIC_PROFILE="${OUTDIR}/numeric_profile.tsv"

awk -F'\t' -v OFS='\t' '

## define function isnum() to check if string is numeric using regex
function isnum(x){ return x ~ /^-?[0-9]+(\.[0-9]+)?$/ }

NR==1{
  for(i=1;i<=NF;i++){ 
    if($i ~ /Score$|Grade$|Hours$|Level$|Motivation$|Resources$|Courses$|Discussions$|Completion$/) {
      numeric_cols[i] = $i
    }
  }
  next
}

{
  for(i in numeric_cols){
    if($i != "" && $i != "NA" && isnum($i)){
      ### conver string to number
      x = $i + 0 
      col = numeric_cols[i]
      ####count valid values per column
      n[col]++
      ### accumlate sum for mean calculation and squares of variance
      sum[col] += x
      sum2[col] += x*x
      # Track min and max values for each column
      if(!(col in min) || x < min[col]) min[col] = x
      if(!(col in max) || x > max[col]) max[col] = x
    }
  }
}

END{
  print "column","count","mean","std","min","max"
  for(col in n){
    if(n[col] >= 5){
      mean = sum[col]/n[col]
      variance = (sum2[col]/n[col]) - (mean*mean)
      if(variance < 0) variance = 0
      std = sqrt(variance)
      printf "%s\t%d\t%.2f\t%.2f\t%.2f\t%.2f\n", col, n[col], mean, std, min[col], max[col]
    }
  }
}
' "$CATEGORIZED" | sort -t$'\t' -k1,1 > "$NUMERIC_PROFILE"

echo "Wrote numeric profile -> $NUMERIC_PROFILE" >&3

### 7B) Outlier flags via z-scores (all numeric columns)

OUTLIERS="${OUTDIR}/outliers.tsv"

# extract means and stds for all numeric columns
awk -F'\t' -v OFS='\t' '
NR==1 {next}
{
    means[$1] = $3
    stds[$1] = $4
}
' "$NUMERIC_PROFILE" > "${TMPDIR}/stats.tsv"

# Detect outliers across all numeric columns
awk -F'\t' -v OFS='\t' '
function z(v,m,s){ 
    if(v==""||v=="NA"||s==0) return "NA" 
    v+=0; 
    return (v-m)/s 
}

NR==1 {
    # Load statistics for all numeric columns
    while((getline line < "'"${TMPDIR}/stats.tsv"'") > 0) {
        split(line, s, "\t")
        means[s[1]] = s[2]
        stds[s[1]] = s[3]
    }
    
    # Build column map
    for(i=1;i<=NF;i++) {
        h[$i]=i
        if($i in means) numeric_cols[i] = $i
    }
    print "RowID","Column","Value","Z_Score","Outlier_Type"
}

NR>1 {
    for(i in numeric_cols) {
        col = numeric_cols[i]
        value = $i
        if(value != "" && value != "NA") {
            z_score = z(value, means[col], stds[col])
            if(z_score != "NA" && (z_score > 2.5 || z_score < -2.5)) {
                outlier_type = (z_score > 2.5) ? "HIGH" : "LOW"
                printf "%d\t%s\t%s\t%.3f\t%s\n", NR-1, col, value, z_score, outlier_type
            }
        }
    }
}
' "$CATEGORIZED" | sort -t$'\t' -k4,4nr > "$OUTLIERS"

echo "Wrote outliers -> $OUTLIERS" >&3

### 7C) Category-wise comparisons of averages/rates

CATEGORY_COMPARISONS="${OUTDIR}/category_comparisons.tsv"

awk -F'\t' -v OFS='\t' '
NR==1 {
    # Identify categorical and performance columns
    for(i=1;i<=NF;i++) {
        if($i ~ /Label$|Letter$|Level$|Style$/) {
            cat_cols[i] = $i
        } else if($i ~ /ExamScore|FinalGrade|StudyHours/) {
            num_cols[i] = $i
        }
    }
}

NR>1 {
    # Calculate overall statistics for baseline comparison
    for(num_idx in num_cols) {
        if($num_idx ~ /^-?[0-9]/) {
            num_field = num_cols[num_idx]
            overall_sum[num_field] += $num_idx + 0
            overall_count[num_field]++
        }
    }
    
    # Accumulate category group statistics
    for(cat_idx in cat_cols) {
        cat_val = $cat_idx
        if(cat_val == "" || cat_val == "NA") cat_val = "MISSING"
        
        for(num_idx in num_cols) {
            if($num_idx ~ /^-?[0-9]/) {
                key = cat_cols[cat_idx] "|" cat_val "|" num_cols[num_idx]
                value = $num_idx + 0
                count[key]++
                sum[key] += value
            }
        }
    }
}

END {
    # Calculate overall means
    for(num_field in overall_sum) {
        overall_mean[num_field] = overall_sum[num_field] / overall_count[num_field]
    }
    
    print "Category","Group","Metric","Count","Group_Mean","Overall_Mean","Difference","Percent_Diff"
    
    for(key in count) {
        split(key, parts, "|")
        cat_field = parts[1]
        cat_val = parts[2] 
        num_field = parts[3]
        
        group_mean = sum[key] / count[key]
        diff = group_mean - overall_mean[num_field]
        percent_diff = (overall_mean[num_field] != 0) ? (diff / overall_mean[num_field]) * 100 : 0
        
        printf "%s\t%s\t%s\t%d\t%.2f\t%.2f\t%+.2f\t%+.1f%%\n",
               cat_field, cat_val, num_field, count[key], group_mean, 
               overall_mean[num_field], diff, percent_diff
    }
}
' "$CATEGORIZED" | sort -t$'\t' -k1,1 -k3,3 -k7,7nr > "$CATEGORY_COMPARISONS"

echo "Wrote category comparisons -> $CATEGORY_COMPARISONS" >&3

### 7D) Ranked "signals" table
SIGNALS="${OUTDIR}/signals.tsv"

{
    echo -e "signal_type\tsignal_description\timpact_score\tpriority"
    
    # 1. Significant performance gaps (positive)
    awk -F'\t' 'NR>1 && $7 > 15 && $4 > 10 {print "performance_gap", $2 " in " $1 " excels at " $3 " (+" $7 " points)", $7, "HIGH"}' "$CATEGORY_COMPARISONS" | head -5
    
    # 2. Concerning performance gaps (negative)  
    awk -F'\t' 'NR>1 && $7 < -15 && $4 > 10 {print "performance_gap", $2 " in " $1 " struggles with " $3 " (" $7 " points)", (-$7), "HIGH"}' "$CATEGORY_COMPARISONS" | head -5
    
    # 3. Extreme outliers
    awk -F'\t' 'NR>1 && ($4 > 3.0 || $4 < -3.0) {print "extreme_outlier", "Row " $1 " extreme " $2 " value: " $3 " (z=" $4 ")", (($4>0)?$4:-$4), "HIGH"}' "$OUTLIERS" | head -3
    
    # 4. High variability metrics
   awk -F'\t' '
NR>1 {
  m=$3+0; s=$4+0;
  if (m!=0 && s/m > 0.3)
    print "high_variability", $1 " has high variability (std=" s ")", (s/m), "MEDIUM"
}
' "$NUMERIC_PROFILE" | head -3 
    # 5. Data quality signals
    TOTAL_OUTLIERS=$(awk 'NR>1' "$OUTLIERS" | wc -l | awk '{print $1}')
    echo -e "data_quality\t${TOTAL_OUTLIERS} statistical outliers detected\t${TOTAL_OUTLIERS}\tMEDIUM"
    
    # 6. Large percentage differences
    awk -F'\t' 'NR>1 && $8 ~ /\+[0-9]+%/ && $8 != "+0.0%" && $4 > 5 {print "percentage_gap", $2 " in " $1 " has " $8 " difference in " $3, ($7/5), "MEDIUM"}' "$CATEGORY_COMPARISONS" | head -3
    
} | sort -t$'\t' -k3,3nr > "$SIGNALS"

   echo "Wrote ranked signals -> $SIGNALS" >&3

















########################################
# Save col cardinality summary and top columns metadata
########################################
sort -t$'\t' -k3,3n "${TMPDIR}/col_cardinality.tsv" > "${OUTDIR}/col_cardinality.tsv"
echo "Wrote column cardinality -> ${OUTDIR}/col_cardinality.tsv" >&3

########################################
# Final notes & cleanup
########################################
echo "Cleanup tmpdir: $TMPDIR" >&3
# keep TMPDIR for debugging (comment out rm -rf if you prefer)
rm -rf "$TMPDIR"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] DONE $me" >&3
echo "All outputs are in $OUTDIR; logs in $LOGDIR"



