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
OUTDIR="out"
LOGDIR="logs"
TMPDIR="$(mktemp -d)"
CLEANED="${TMPDIR}/cleaned.tsv"
BEFORE_SAMPLE="${OUTDIR}/before_sample.tsv"
AFTER_SAMPLE="${OUTDIR}/after_sample.tsv"
HEADER_FILE="${TMPDIR}/header.tsv"
DETECTED_DELIM=""
NUM_COLS=0

mkdir -p "$OUTDIR" "$LOGDIR"
exec 3>"$LOGDIR/run_pa4.log"
echo "[$(date -u +%Y-%m-%dT%h:%M:%SZ:)] START $me" >&3

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
##########################################################################

### 5A  Derived ratios
## Define the output path 
RATIOS="${OUTDIR}/with_ratios.tsv"

awk -F'\t' -v OFS='\t' '

NR==1{
for(i=1;i<=NF;i++) h[$i]=i
#add new derived columns at the end

print $0, "StudyEfficiency(FinalGrade/Study Hours)", "StressToMotivation(StressLevel/(Motivation+1))", "Engagement((Discussions+Online Courses)/(Resources+1))"
next

}

{
   # Pull fields
  sg = ($(h["StudyHours"])=="NA"?0:$(h["StudyHours"])+0)
  fg = ($(h["FinalGrade"])=="NA"?0:$(h["FinalGrade"])+0)
  st = ($(h["StressLevel"])=="NA"?0:$(h["StressLevel"])+0)
  mt = ($(h["Motivation"])=="NA"?0:$(h["Motivation"])+0)
  rs = ($(h["Resources"])=="NA"?0:$(h["Resources"])+0)
  dc = ($(h["Discussions"])=="NA"?0:$(h["Discussions"])+0)
  oc = ($(h["OnlineCourses"])=="NA"?0:$(h["OnlineCourses"])+0)
  
  
   # Ratios(guarded)
   ## set StudyEfficiency=FinalGrade/StudyHours. If StudyHours==0,set"NA"
   se = (sg>0 ? fg/sg : "NA")

   ## set sm=StressToMovtivation=Stress/(Motivation+1), adding 1 is to make sure the denominatore never   ##### be zero
   sm = st/(mt+1) 
  
   ### set eg=Enagement=((Discussions+OnlineCourses)/(Resources+1)), adding 1 to  make sure the
   #####denominatore never be zero
   eg =(rs+1>0 ? (dc+oc)/(rs+1) : "NA")


   ### Keep numeric ratio to 4 decimal places

   if (se != "NA") se = sprintf("%.4f", se)
   if (sm != "NA") sm = sprintf("%.4f", sm)
   if (eg != "NA") eg = sprintf("%.4f", eg) 
 
  print $0, se, sm, eg
}

' "$FILTERED" > "$RATIOS"

 echo "Wrote ratios -> $RATIOS" >&3

 

### 5B Buckets change numeric -> categorical && bucket counts

 BUCKETS="${OUTDIR}/with_buckets.tsv"

#### Convert the numeric value to ZERO,LO,MID,HI, but keep "NA" as "NA"

awk -F'\t' -v OFS='\t' '
function bucket(x, v){
   if(x=="NA"|| x=="") return "NA"
   v = x + 0
   if(v<=0) return "ZERO"
   else if (v<50) return "LO"
   else if (v<75) return "MID"
   else return "HI"
}


### build header map and print the original header with two new columns name

NR==1{
  for(i=1;i<=NF;i++) h[$i]=i
  print $0, "ExamScoreBucket","FinalGradeBucket"
  next
}

{
  es = (h["ExamScore"]  ? $(h["ExamScore"])  : "NA")
  fg = (h["FinalGrade"] ? $(h["FinalGrade"]) : "NA")
  if (es == "") es = "NA"
  if (fg == "") fg = "NA"
  print $0, bucket(es), bucket(fg)
}
' "$FILTERED" > "$BUCKETS"



##### Bucket Frequencies

awk -F'\t' '
NR==1 { next }
{ exam[$1]++; final[$2]++ }
END {
  print "bucket\ttype\tcount";
  for (b in exam)  printf "%s\texam\t%d\n",  b, exam[b];
  for (b in final) printf "%s\tfinal\t%d\n", b, final[b];
}
' "$BUCKETS" | sort -t$'\t' -k2,2 -k1,1 > "${OUTDIR}/bucket_counts.tsv"

echo "Wrote -> $BUCKETS and ${OUTDIR}/bucket_counts.tsv" >&3


########################################
# 5C. Per-entity summary (Gender) — count & averages
########################################
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
  if (idxG==0) next
  g = $idxG
  if (g=="" || g==" ") g="NA"

  cnt[g]++

  if (idxES>0) {
    es = $idxES
    if (es!="" && es!="NA") { es+=0; sum_es[g]+=es; n_es[g]++ }
  }
  if (idxFG>0) {
    fg = $idxFG
    if (fg!="" && fg!="NA") { fg+=0; sum_fg[g]+=fg; n_fg[g]++ }
  }
}
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

SUMMARY_LS="${OUTDIR}/summary_by_learningstyle.tsv"

awk -F'\t' -v OFS='\t' '
NR==1{for(i=1;i<=NF;i++) h[$i]=i; next}
{
  s = $(h["LearningStyle"]); if (s=="" || s==" ") s="NA"
  es = $(h["ExamScore"]);  fg = $(h["FinalGrade"])
  cnt[s]++
  if (es!="" && es!="NA"){ es+=0; sum_es[s]+=es; n_es[s]++ }
  if (fg!="" && fg!="NA"){ fg+=0; sum_fg[s]+=fg; n_fg[s]++ }
}
END{
  print "LearningStyle","Count","AvgExam","AvgFinal"
  for (k in cnt){
    ae = (n_es[k]? sum_es[k]/n_es[k] : 0)
    af = (n_fg[k]? sum_fg[k]/n_fg[k] : 0)
    printf "%s\t%d\t%.2f\t%.2f\n", k, cnt[k], ae, af
  }
}
' "$FILTERED" | sort -t$'\t' -k1,1 > "$SUMMARY_LS"
echo "Wrote learning style -> $SUMMARY_LS" >&3



########################################
# 5) String structure (no time column)
#    - Turn numeric/boolean fields into readable string categories
#    - Profile distributions (freq tables) deterministically
########################################


# 5A) Create human-readable string categories:
#     - FinalLetter: A/B/C/D/F from FinalGrade
#     - ExamBandText: LOW/MID/HIGH from ExamScore (match your buckets)
#     - Bool labels for Internet/EduTech/Gender -> Yes/No/NA

# --- Step 5A: derive FinalLetter (A/B/C/D/F) from FinalGrade ---
WITH_LETTERS="${OUTDIR}/with_finalletter.tsv"

awk -F'\t' -v OFS='\t' '
NR==1{
  for(i=1;i<=NF;i++) h[$i]=i
  print $0, "FinalLetter"
  next
}
{
  fg = (("FinalGrade" in h) ? $(h["FinalGrade"]) : "")
  if (fg=="" || fg=="NA") {
    letter = "NA"
  } else {
    g = fg + 0
    # Auto-detect scale: if value <=10, treat as 0–10; else 0–100
    if (g <= 10) {
      letter = (g>=9 ? "A" : (g>=8 ? "B" : (g>=7 ? "C" : (g>=6 ? "D" : "F"))))
    } else {
      letter = (g>=90 ? "A" : (g>=80 ? "B" : (g>=70 ? "C" : (g>=60 ? "D" : "F"))))
    }
  }
  print $0, letter
}
' "$FILTERED" > "$WITH_LETTERS"

echo "Wrote final-letter file -> $WITH_LETTERS" >&3

# Frequency table for FinalLetter (deterministic sort)
awk -F'\t' '
NR==1{
  for(i=1;i<=NF;i++) if($i=="FinalLetter") c=i; next
}
{ if (c>0 && $c!="") cnt[$c]++ }
END{
  print "FinalLetter\tcount"
  for (k in cnt) printf "%s\t%d\n", k, cnt[k]
}
' "$WITH_LETTERS" | sort -t$'\t' -k2,2nr -k1,1 > "${OUTDIR}/freq_FinalLetter.tsv"

echo "Wrote -> ${OUTDIR}/freq_FinalLetter.tsv" >&3


# --- 5B: ExamBandText from ExamScore ---
WITH_EXAMBAND="${OUTDIR}/with_examband.tsv"

awk -F'\t' -v OFS='\t' '
function exmband(s){ if(s==""||s=="NA")return "NA"; s+=0; return (s<50?"LOW":(s<75?"MID":"HIGH")) }
NR==1{ for(i=1;i<=NF;i++) h[$i]=i; print $0,"ExamBandText"; next }
{
  es = (("ExamScore" in h)? $(h["ExamScore"]) : "NA")
  print $0, exmband(es)
}
' "$FILTERED" > "$WITH_EXAMBAND"

echo "Wrote exam-band file -> $WITH_EXAMBAND" >&3

# Frequency of the bands
awk -F'\t' '
NR==1{for(i=1;i<=NF;i++) if($i=="ExamBandText") idx=i; next}
{ if(idx>0) c[$idx]++ }
END{ print "ExamBandText\tcount"; for(k in c) printf "%s\t%d\n", k, c[k] }
' "$WITH_EXAMBAND" | sort -t$'\t' -k2,2nr -k1,1 > "${OUTDIR}/freq_ExamBandText.tsv"




# --- 5C: Readable string labels + combine derived fields ---
STRING_OUT="${OUTDIR}/string_features.tsv"

awk -F'\t' -v OFS='\t' '
function yn(x){ if(x==""||x=="NA")return "NA"; x+=0; return (x==1?"Yes":(x==0?"No":x)) }
function genderlab(x){ if(x==""||x=="NA")return "NA"; x+=0; return (x==1?"Female":(x==0?"Male":x)) }
function exmband(s){ if(s==""||s=="NA")return "NA"; s+=0; return (s<50?"LOW":(s<75?"MID":"HIGH")) }
function finalletter(f){
  if(f==""||f=="NA")return "NA"; f+=0;
  if(f<=10) return (f>=9?"A":(f>=8?"B":(f>=7?"C":(f>=6?"D":"F"))));
  return (f>=90?"A":(f>=80?"B":(f>=70?"C":(f>=60?"D":"F"))))
}
NR==1{
  for(i=1;i<=NF;i++) h[$i]=i
  print $0, "GenderLabel","InternetLabel","EduTechLabel","ExamBandText","FinalLetter"
  next
}
{
  g  = (("Gender"     in h)? $(h["Gender"])     : "NA")
  net= (("Internet"   in h)? $(h["Internet"])   : "NA")
  et = (("EduTech"    in h)? $(h["EduTech"])    : "NA")
  es = (("ExamScore"  in h)? $(h["ExamScore"])  : "NA")
  fg = (("FinalGrade" in h)? $(h["FinalGrade"]) : "NA")
  print $0, genderlab(g), yn(net), yn(et), exmband(es), finalletter(fg)
}
' "$FILTERED" > "$STRING_OUT"

echo "Wrote derived string features -> $STRING_OUT" >&3

####################################################################
# 6. SignSignal discovery" tailored to your feature types
#  distribution profiles (mean, std, min, max)
# outlier flags via simple z-scores or high-percentile thresholds (computed with AWK + sort)
# category-wise comparisons of averages or rates.
# Either way, emit a ranked "signals" table to out/.
# 
#######################################################################
# 6A) Numeric profiles: mean, std, min, max
########################################

NUMERIC_PROFILE="${OUTDIR}/numeric_profile.tsv"

awk -F'\t' -v OFS='\t' '
function isnum(x){ return x ~ /^-?[0-9]+(\.[0-9]+)?$/ }

NR==1{
  for(i=1;i<=NF;i++){ H[i]=$i }   # index -> header
  next
}

{
  for(i=1;i<=NF;i++){
    col = H[i]
    v   = $i
    if(v != "" && v != "NA"){
      seen[col]++
      if(isnum(v)){
        x = v + 0
        numc[col]++
        n[col]++
        s[col]  += x
        s2[col] += x*x
        if(!(col in mn) || x < mn[col]) mn[col] = x
        if(!(col in mx) || x > mx[col]) mx[col] = x
      }
    }
  }
}

END{
  thr = 0.80  # keep columns where ≥80% of non-NA values are numeric
  print "column","count","mean","std","min","max"
  for(col in seen){
    share = (seen[col] > 0 ? numc[col]/seen[col] : 0)
    if (share >= thr && n[col] > 0){
      m   = s[col]/n[col]
      var = (s2[col]/n[col]) - (m*m)
      if (var < 0) var = 0
      sd  = sqrt(var)
      printf "%s\t%d\t%.4f\t%.4f\t%.4f\t%.4f\n", col, n[col], m, sd, mn[col], mx[col]
    }
  }
}
' "$FILTERED" | sort -t$'\t' -k1,1 > "$NUMERIC_PROFILE"

echo "Wrote numeric profile -> $NUMERIC_PROFILE" >&3



########################################
# 6B) Outlier flags (z-scores) for ExamScore & FinalGrade
########################################
# Pull means/std from the numeric profile
ES_MEAN=$(awk -F'\t' '$1=="ExamScore"{print $3}' "$NUMERIC_PROFILE")
ES_STD=$(awk  -F'\t' '$1=="ExamScore"{print $4}' "$NUMERIC_PROFILE")
FG_MEAN=$(awk -F'\t' '$1=="FinalGrade"{print $3}' "$NUMERIC_PROFILE")
FG_STD=$(awk  -F'\t' '$1=="FinalGrade"{print $4}' "$NUMERIC_PROFILE")

OUTLIERS="${OUTDIR}/outliers.tsv"
awk -F'\t' -v OFS='\t' -v es_m="$ES_MEAN" -v es_s="$ES_STD" -v fg_m="$FG_MEAN" -v fg_s="$FG_STD" '
function z(v,m,s){ if(v==""||v=="NA"||s==0) return "NA"; v+=0; return (v-m)/s }
NR==1{
  for(i=1;i<=NF;i++) h[$i]=i
  print "RowID","ExamScore","z_exam","FinalGrade","z_final"
  next
}
{
  es = $(h["ExamScore"])
  fg = $(h["FinalGrade"])
  ze = z(es, es_m, es_s)
  zf = z(fg, fg_m, fg_s)
  # flag if either |z| >= 2.5
  keep=0
  if (ze!="NA" && (ze>2.5 || ze<-2.5)) keep=1
  if (zf!="NA" && (zf>2.5 || zf<-2.5)) keep=1
  if (keep) printf "%d\t%s\t%s\t%s\t%s\n", NR-1, es, (ze=="NA"?"NA":sprintf("%.3f",ze)), fg, (zf=="NA"?"NA":sprintf("%.3f",zf))
}
' "$FILTERED" \
| sort -t$'\t' -k3,3nr -k5,5nr \
| head -n 200 > "$OUTLIERS"
echo "Wrote outliers -> $OUTLIERS" >&3




########################################
# 6C) Category-wise comparisons (avg by group)
########################################
AVG_GENDER="${OUTDIR}/avg_by_gender.tsv"
awk -F'\t' -v OFS='\t' '
NR==1{ for(i=1;i<=NF;i++) h[$i]=i; next }
{
  g  = (("GenderLabel" in h)? $(h["GenderLabel"]) : (("Gender" in h)?$(h["Gender"]):"NA"))
  es = (("ExamScore"   in h)? $(h["ExamScore"])   : "NA")
  fg = (("FinalGrade"  in h)? $(h["FinalGrade"])  : "NA")
  if (g==""||g=="NA") g="NA"
  if (es!=""&&es!="NA") { es+=0; s_es[g]+=es; n_es[g]++ }
  if (fg!=""&&fg!="NA") { fg+=0; s_fg[g]+=fg; n_fg[g]++ }
}
END{
  print "Group","avg_exam","avg_final","n_exam","n_final"
  for (g in s_es) { ; } # touch to ensure assoc created
  # union of groups across es/fg
  PROCINFO["sorted_in"]="@ind_str_asc"
  for (g in n_es) {
    ae = (n_es[g]>0 ? s_es[g]/n_es[g] : 0)
    af = (g in n_fg && n_fg[g]>0 ? s_fg[g]/n_fg[g] : 0)
    printf "%s\t%.2f\t%.2f\t%d\t%d\n", g, ae, af, (n_es[g]+0), (n_fg[g]+0)
  }
  for (g in n_fg) if (!(g in n_es)) {
    ae = 0; af = (n_fg[g]>0 ? s_fg[g]/n_fg[g] : 0)
    printf "%s\t%.2f\t%.2f\t%d\t%d\n", g, ae, af, 0, (n_fg[g]+0)
  }
}
' "$STRING_OUT" | sort -t$'\t' -k3,3nr > "$AVG_GENDER"
echo "Wrote averages by gender -> $AVG_GENDER" >&3

AVG_LS="${OUTDIR}/avg_by_learningstyle.tsv"
awk -F'\t' -v OFS='\t' '
NR==1{ for(i=1;i<=NF;i++) h[$i]=i; next }
{
  s  = (("LearningStyle" in h)? $(h["LearningStyle"]) : "NA")
  es = (("ExamScore"     in h)? $(h["ExamScore"])     : "NA")
  fg = (("FinalGrade"    in h)? $(h["FinalGrade"])    : "NA")
  if (s==""||s=="NA") s="NA"
  if (es!=""&&es!="NA") { es+=0; s_es[s]+=es; n_es[s]++ }
  if (fg!=""&&fg!="NA") { fg+=0; s_fg[s]+=fg; n_fg[s]++ }
}
END{
  print "LearningStyle","avg_exam","avg_final","n_exam","n_final"
  for (s in n_es) {
    ae = (n_es[s]>0 ? s_es[s]/n_es[s] : 0)
    af = (s in n_fg && n_fg[s]>0 ? s_fg[s]/n_fg[s] : 0)
    printf "%s\t%.2f\t%.2f\t%d\t%d\n", s, ae, af, (n_es[s]+0), (n_fg[s]+0)
  }
  for (s in n_fg) if (!(s in n_es)) {
    ae = 0; af = (n_fg[s]>0 ? s_fg[s]/n_fg[s] : 0)
    printf "%s\t%.2f\t%.2f\t%d\t%d\n", s, ae, af, 0, (n_fg[s]+0)
  }
}
' "$STRING_OUT" | sort -t$'\t' -k3,3nr > "$AVG_LS"
echo "Wrote averages by learning style -> $AVG_LS" >&3





########################################
# 6D) Signals roll-up (ranked)
#  take top5 rows from avg_by_gender.tsv and avg_by_learningstyle.tsv
#
#
#
########################################
SIGNALS="${OUTDIR}/signals.tsv"

# 1) Top groups by FinalGrade (gender + learning style, top 5 each)
{
  echo -e "signal\tscore\tsource"
  tail -n +2 "$AVG_GENDER"       | head -n 5 | awk -F'\t' -v OFS='\t' '{printf "Top gender avg_final: %s\t%.2f\tavg_by_gender\n",$1,$3}'
  tail -n +2 "$AVG_LS"           | head -n 5 | awk -F'\t' -v OFS='\t' '{printf "Top learningstyle avg_final: %s\t%.2f\tavg_by_learningstyle\n",$1,$3}'
  # 2) Outlier intensity (how many z>=2.5 rows)
  if [ -s "$OUTLIERS" ]; then
    OLN=$(wc -l < "$OUTLIERS")
    echo -e "Outlier rows (|z|>=2.5)\t$OLN\toutliers"
  else
    echo -e "Outlier rows (|z|>=2.5)\t0\toutliers"
  fi
} | sort -t$'\t' -k2,2nr -k1,1 > "$SIGNALS"

echo "Wrote signals -> $SIGNALS" >&3





















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


