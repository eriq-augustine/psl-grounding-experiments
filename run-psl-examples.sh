#!/bin/bash

readonly BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly BASE_OUT_DIR="${BASE_DIR}/results"

readonly PSL_EXAMPLES_DIR="${BASE_DIR}/psl-examples"
readonly PSL_EXAMPLES_REPO='https://github.com/linqs/psl-examples.git'
readonly PSL_EXAMPLES_BRANCH='develop'

readonly SPECIAL_DATA_DIR="${BASE_DIR}/special-data"
readonly OTHER_EXAMPLE_DIR="${BASE_DIR}/other-examples"

readonly POSTGRES_DB='psl'
readonly BASE_PSL_OPTION="--postgres ${POSTGRES_DB} -D log4j.threshold=TRACE -D persistedatommanager.throwaccessexception=false -D grounding.serial=true"

readonly EXPERIMENT_NAMES=('no_rewrites' 'size_rewrites' 'selectivity_rewrites' 'histogram_rewrites')
readonly EXPERIMENT_OPTIONS=('-D grounding.rewritequeries=false' '-D grounding.rewritequeries=true -D queryrewriter.costestimator=size' '-D grounding.rewritequeries=true -D queryrewriter.costestimator=selectivity' '-D grounding.rewritequeries=true -D queryrewriter.costestimator=histogram')

# Examples that cannot use int ids.
readonly STRING_IDS='entity-resolution simple-acquaintances user-modeling'

readonly NUM_RUNS=20

readonly STDOUT_FILE='out.txt'
readonly STDERR_FILE='out.err'

readonly ER_DATA_SZIE='large'

readonly MEM_GB='25'

function fetch_psl_examples() {
   if [ -e ${PSL_EXAMPLES_DIR} ]; then
      return
   fi

   git clone ${PSL_EXAMPLES_REPO} ${PSL_EXAMPLES_DIR}

   pushd . > /dev/null
      cd "${PSL_EXAMPLES_DIR}"
      git checkout ${PSL_EXAMPLES_BRANCH}
   popd > /dev/null

   # Special fixes.

   # Change the size of the ER example to the max size.
   sed -i "s/^readonly SIZE='.*'$/readonly SIZE='${ER_DATA_SZIE}'/" "${PSL_EXAMPLES_DIR}/entity-resolution/data/fetchData.sh"

   # Replace the data in friendship
   rm -r "${PSL_EXAMPLES_DIR}/friendship/data/friendship"
   cp -r "${SPECIAL_DATA_DIR}/friendship" "${PSL_EXAMPLES_DIR}/friendship/data/friendship"

   # Copy in pairwise friendship
   cp -r "${OTHER_EXAMPLE_DIR}/friendship-pairwise" "${PSL_EXAMPLES_DIR}/"
}

function run_example() {
   local exampleBaseDir=$1
   local options=$2
   local outDir=$3

   if [ -e "${outDir}" ]; then
      echo "Founding existing out directory, skipping. ${outDir}"
      return
   fi

   # TEST(eriq): Skip this for now until we move it to a larger machine.
   if [[ "${outDir}" == *'entity-resolution/size_rewrites'* ]]; then
      echo "Skipping ER-Size"
      return
   fi

   local baseName=`basename ${exampleBaseDir}`

   echo "Running ${baseName} (${outDir})."
   mkdir -p "${outDir}"

   local outStdoutPath="${outDir}/${STDOUT_FILE}"
   local outStderrPath="${outDir}/${STDERR_FILE}"

   # Check for int ids.
   if [[ "${STRING_IDS}" != *"${baseName}"* ]]; then
      options="--int-ids ${options}"
   fi

   pushd . > /dev/null
      cd "${exampleBaseDir}/cli"

      # Always create a -leared version of the model in case this example has weight learning.
      cp "${baseName}.psl" "${baseName}-learned.psl"

      # Increase memory allocation.
      sed -i "s/java -jar/java -Xmx${MEM_GB}G -Xms${MEM_GB}G -jar/" run.sh

      # Disable weight learning.
      sed -i 's/^\(\s\+\)runWeightLearning/\1# runWeightLearning/' run.sh

      # Add in the additional options.
      sed -i "s/^readonly ADDITIONAL_PSL_OPTIONS='.*'$/readonly ADDITIONAL_PSL_OPTIONS='${BASE_PSL_OPTION} ${options}'/" run.sh

      # Disable evaluation, we only really want grounding.
      sed -i "s/^readonly ADDITIONAL_EVAL_OPTIONS='.*'$/readonly ADDITIONAL_EVAL_OPTIONS='--infer'/" run.sh

      /usr/bin/time -v ./run.sh > "${outStdoutPath}" 2> "${outStderrPath}"
   popd > /dev/null
}

function main() {
   trap exit SIGINT

   fetch_psl_examples
   mkdir -p "${BASE_OUT_DIR}"

   for exampleDir in `find ${PSL_EXAMPLES_DIR} -maxdepth 1 -mindepth 1 -type d -not -name '.git'`; do
      for experimentIndex in "${!EXPERIMENT_NAMES[@]}"; do
         for run in `seq -w ${NUM_RUNS}`; do
            local experimentName="${EXPERIMENT_NAMES[$experimentIndex]}"
            local experimentOptions="${EXPERIMENT_OPTIONS[$experimentIndex]}"
            local example=`basename ${exampleDir}`
            local outDir="${BASE_OUT_DIR}/${example}/${experimentName}/${run}"

            run_example "${exampleDir}" "${experimentOptions}" "${outDir}"
         done
      done
   done

   exit 0
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
