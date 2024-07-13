TOMCAT_VERSION=11.0.0-M22
rm -rf ASF MY
mkdir ASF
mkdir MY

TOMCAT_MAJOR=`echo "$TOMCAT_VERSION"  | awk -F '.' '{print $1}'`

# Use 21/22 for tomcat11
# /usr/lib/jvm/java-21-openjdk
if [ $TOMCAT_MAJOR == 11 ]; then
  # export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
  # export PATH=$JAVA_HOME/bin:$PATH
  # export JAVA_HOME=/home/jfclere/JAVA/jdk-22
  export JAVA_HOME=/home/jfclere/JAVA/jdk-22.0.1
  export PATH=$JAVA_HOME/bin:$PATH
fi

# check java version
JAVA_VERSION=`java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}'`
JAVA_MAJOR=`echo "$JAVA_VERSION"  | awk -F '.' '{print $1}'`
if [ $TOMCAT_MAJOR == "9" ]; then
  echo "tomcat 9!!!"
  if [ $JAVA_MAJOR != "17" ]; then
    echo "Wrong java version needs 17"
    exit 1
  fi
  # check the version in ant (probably via $JAVA_HOME)
  JAVA_VERSION=`ant | grep java-version: | awk '{print $3}'`
  JAVA_MAJOR=`echo "$JAVA_VERSION"  | awk -F '.' '{print $1}'`
  if [ $JAVA_MAJOR == "17" ]; then
    echo "ant uses $JAVA_VERSION"
  else
    echo "Wrong java version tomcat needs 17 and ant uses $JAVA_VERSION"
    exit 1
  fi
fi

# Check build.properties.release
# the JAVA version is there...
JAVA_RELEASE_VERSION=`grep release-java-version apache-tomcat-${TOMCAT_VERSION}-src/build.properties.release | awk -F = '{ print $2 }'`
if [ ${JAVA_RELEASE_VERSION} != ${JAVA_VERSION} ]; then
  echo "JAVA_RELEASE_VERSION: $JAVA_RELEASE_VERSION"
  echo "JAVA_VERSION: $JAVA_VERSION"
fi
# ./apache-tomcat-11.0.0-M22-src/build.properties.release

(cd apache-tomcat-${TOMCAT_VERSION}-src; ant clean)
(cd apache-tomcat-${TOMCAT_VERSION}-src; ant release)

echo "release rebuilt testing it"

(cd ASF; tar xf ../apache-tomcat-${TOMCAT_VERSION}.tar.gz)
(cd MY; tar xf ../apache-tomcat-${TOMCAT_VERSION}-src/output/release/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz)

echo "Testing for no jar files"
diff -ru ASF MY | grep -v jar
if [ $? -eq 0 ]; then
  echo "Oops some is wrong, not only jar difference"
  exit 1
fi

echo "Testing for jar files"
for file in `(cd ASF; find . -name "*.jar")`
do
  echo "testing: $file"
  file=`echo $file | sed "s/.//"`
  rm -rf JARASF; mkdir JARASF
  rm -rf JARMY; mkdir JARMY
  (cd JARASF; jar xf ../ASF/${file})
  (cd JARMY; jar xf ../MY/${file})
  rm -f JARASF/META-INF/MANIFEST.MF
  rm -f JARMY/META-INF/MANIFEST.MF
  diff -ru JARASF JARMY
  if [ $? -ne 0 ]; then
    echo "Oops some is wrong, jar $file are different"
    exit 1
  fi
done
