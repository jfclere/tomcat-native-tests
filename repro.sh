mkdir ASF
mkdir MY

(cd ASF; tar xf ../apache-tomcat-10.1.17.tar.gz)
(cd MY; tar xf ../apache-tomcat-10.1.17-src/output/release/v10.1.17/bin/apache-tomcat-10.1.17.tar.gz)

diff -ru ASF MY | grep -v jar
if [ $? -eq 0 ]; then
  echo "Oops some is wrong, not only jar difference"
  exit 1
fi

for file in `(cd ASF; find . -name "*.jar")`
do
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
