#!/bin/bash
# ============================================================
# This script is used to run the pipeline on a single project.
# ============================================================

# Input arguments
REPO_NAME=$1;
GITHUB_URL=$2;
MODULE_DIR=$3;
RELEASE=$4;
COMMIT=$5;

# Variables
PROJECTS_DIR="projects"
RESULTS_DIR="results"
logger_deptrim="[DEPTRIM]"
logger_maven="[MAVEN]"
logger_pipeline="[PIPELINE]"
CURRENT_DIR=$(pwd)

# Create data storage directories
mkdir -p "$CURRENT_DIR"/"$PROJECTS_DIR"
mkdir -p "$CURRENT_DIR"/"$RESULTS_DIR"
mkdir -p "$CURRENT_DIR"/"$RESULTS_DIR"/"$REPO_NAME"

# Clone the repo from URL
echo "====================================================="
echo "${logger_pipeline} Cloning $REPO_NAME"
cd "$CURRENT_DIR"/$PROJECTS_DIR
git clone --quiet "$GITHUB_URL"

# CD into the project directory
echo "${logger_pipeline} CDing into $REPO_NAME"
cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"

# Checkout the release
echo "${logger_pipeline} Checking out version $RELEASE at commit $COMMIT"
git checkout --quiet "$COMMIT"

# CD into the module if any
if [ -z "$MODULE_DIR" ]; then
  echo "${logger_pipeline} Project is single-module, will build $REPO_NAME"
  cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"
else
  echo "${logger_pipeline} Project is multi-module, CDing into $MODULE_DIR"
  cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"/"$MODULE_DIR"
fi

# Run the pipeline from module directory if any
echo "=========================================================================================="
echo "${logger_pipeline} Building original project and storing results in $REPO_NAME/$MODULE_DIR/original"
mkdir original
cp pom.xml pom-original.xml
cp pom.xml original/pom-original.xml
mvn clean package -q -Dcheckstyle.skip -DskipITs -Drat.skip=true -Dtidy.skip=true -Denforcer.skip=true >> original/maven.log
cp target/*.jar original/
mvn dependency:copy-dependencies -DincludeScope=runtime >> original/compile-scope-dependencies.log
mkdir original/compile-scope-dependencies/
cp -r target/dependency original/compile-scope-dependencies/
mvn dependency:copy-dependencies >> original/all-dependencies.log
mkdir original/all-dependencies/
cp -r target/dependency original/all-dependencies/
mvn dependency:tree >> original/dependency-tree.log
mvn dependency:list >> original/dependency-list.log

# RUN DEPTRIM
echo "====================================================="
echo "${logger_deptrim} Running DepTrim"
mkdir deptrim
mvn se.kth.castor:deptrim-maven-plugin:0.1.1:deptrim -DcreateDependencySpecializedPerPom=true -DverboseMode=true -DignoreScopes=test,provided,system,import,runtime >> deptrim/deptrim.log
cp -r libs-specialized deptrim

# EXECUTING POMS
echo "====================================================="
echo "${logger_deptrim} Number of poms generated by DepTrim:"
poms=`find . -name "pom-specialized*.xml"`
echo "${poms}"

for i in ${poms}
do
  length=${#i}
  cut_length=$((length-4))
  specialized_pom=`echo ${i} | cut -c 3-`
  # create a folder for the specialized pom
  output=`echo ${i} | cut -c 3-${cut_length}`
  mkdir ${output}
  cp ${specialized_pom} ${output}/
  # Setting as main pom
  mv ${specialized_pom} pom.xml
  # Running mvn clean package
  echo "====================================================="
  echo "${logger_pipeline} Building with ${specialized_pom}"
  mvn clean package -q -Dcheckstyle.skip -DskipITs -Drat.skip=true -Dtidy.skip=true -Denforcer.skip=true >> ${output}/maven.log
  mvn dependency:tree >> ${output}/dependency-tree.log
  cp target/*.jar ${output}/
  # Restoring pom number
  mv pom.xml ${specialized_pom}
done

# RUN DEPCLEAN
echo "====================================================="
echo "${logger_deptrim} Running DepClean"
if [ -z "$MODULE_DIR" ]; then
  # shellcheck disable=SC2164
  cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"
else
  # shellcheck disable=SC2164
  cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"/"$MODULE_DIR"
fi
mv pom-original.xml pom.xml
mkdir depclean
mvn -q clean compile -q
mvn -q compiler:testCompile -q
mvn se.kth.castor:depclean-maven-plugin:2.0.5:depclean -DcreatePomDebloated=true >> pom-debloated/depclean.log

# BUILD WITH pom-debloated.xml
echo "====================================================="
echo "${logger_pipeline}  Building with pom-debloated.xml"
if [ -z "$MODULE_DIR" ]; then
  # shellcheck disable=SC2164
  cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"
else
  # shellcheck disable=SC2164
  cd "$CURRENT_DIR"/$PROJECTS_DIR/"$REPO_NAME"/"$MODULE_DIR"
fi
mv pom.xml pom-original.xml
mv pom-debloated.xml pom.xml
mkdir pom-debloated
mkdir pom-debloated/target
mvn clean package -q -Dcheckstyle.skip -DskipITs -Drat.skip=true -Dtidy.skip=true -Denforcer.skip=true >> pom-debloated/maven.log
cp target/*.jar pom-debloated/
mvn dependency:copy-dependencies >> pom-debloated/all-dependencies.log
cp -r target/dependency pom-debloated/all-dependencies/
mv pom.xml pom-debloated/pom-debloated.xml

# Restore original pom
echo "====================================================="
echo "${logger_pipeline}  Restoring original pom and exiting"
mv pom-original.xml pom.xml

# Copy the results to the results directory
echo "=========================================================================================="
if [ -z "$MODULE_DIR" ]; then
  echo "${logger_pipeline}  Copying the results to ${CURRENT_DIR}/${RESULTS_DIR}/${REPO_NAME}"
    cp -r . "$CURRENT_DIR"/"$RESULTS_DIR"/"$REPO_NAME"
else
  echo "${logger_pipeline}  Copying the results to ${CURRENT_DIR}/${RESULTS_DIR}/${REPO_NAME}/${MODULE_DIR}"
  cp -r . "$CURRENT_DIR"/"$RESULTS_DIR"/"$REPO_NAME"/"$MODULE_DIR"
fi

exit 0