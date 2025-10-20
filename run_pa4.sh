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
echo "[$(date --iso-8601=seconds)] START $me" >&3

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
s/^\xEF\xBB\xBF//   # remove BOM
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

echo "[$(date --iso-8601=seconds)] DONE $me" >&3
echo "All outputs are in $OUTDIR; logs in $LOGDIR"


