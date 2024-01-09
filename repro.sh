TOMCAT_VERSION=9.0.85
rm -rf ASF MY
mkdir ASF
mkdir MY

(cd apache-tomcat-${TOMCAT_VERSION}-src; ant release)

echo "release rebuilt testing it"

(cd ASF; tar xf ../apache-tomcat-${TOMCAT_VERSION}.tar.gz)
(cd MY; tar xf ../apache-tomcat-${TOMCAT_VERSION}-src/output/release/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz)

diff -ru ASF MY | grep -v jar
if [ $? -eq 0 ]; then
  echo "Oops some is wrong, not only jar difference"
  exit 1
fi

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
