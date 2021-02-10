VERSION=1.2.26
TC_VERSION=9.0.43

# find java_home
JAVA=`which java`
JAVA=`ls -l ${JAVA} | awk '{ print $11 }'`
if [ ! -z ${JAVA} ]; then
  JAVA=`ls -l ${JAVA} | awk '{ print $11 }'`
fi
echo "${JAVA}" | grep jre
if [ $? -eq 0 ]; then
  JAVA_HOME=`echo "${JAVA}" | sed 's:jre: :' | awk ' { print $1 } '`
else
  JAVA_HOME=`echo "${JAVA}" | sed 's:bin: :' | awk ' { print $1 } '`
fi
ENTROPY=`cat /proc/sys/kernel/random/entropy_avail`
if [ $ENTROPY -lt 3000 ]
then
  echo "This box can't do ssl tests... ${ENTROPY} is NOT enough"
  exit 1
fi

echo "Using: $JAVA_HOME"

# Stop running tomcat...
if [ -d apache-tomcat-${TC_VERSION} ]
then
  apache-tomcat-${TC_VERSION}/bin/shutdown.sh
  sleep 10
fi

rm -rf tomcat-native-${VERSION}
rm -f tomcat-native-*
wget https://dist.apache.org/repos/dist/dev/tomcat/tomcat-connectors/native/${VERSION}/source/tomcat-native-${VERSION}-src.tar.gz
if [ $? -ne 0 ]; then
    wget http://mirror.easyname.ch/apache/tomcat/tomcat-connectors/native/${VERSION}/source/tomcat-native-${VERSION}-src.tar.gz
    if [ $? -ne 0 ]; then
      echo "Can't find tomcat-native: ${VERSION}"
      exit 1
    fi 
fi
tar xvf tomcat-native-${VERSION}-src.tar.gz
(cd tomcat-native-${VERSION}-src/native
 ./configure --with-java-home=${JAVA_HOME}
 if [ $? -ne 0 ]; then
   echo "Can't configure tomcat-native: ${VERSION}"
   exit 1
 fi 
 make
) || exit 1

if [ ! -d apache-tomcat-${TC_VERSION} ]
then
  if [ ! -f apache-tomcat-${TC_VERSION}.tar.gz ]
  then
    wget http://mirror.easyname.ch/apache/tomcat/tomcat-9/v${TC_VERSION}/bin/apache-tomcat-${TC_VERSION}.tar.gz
    if [ $? -ne 0 ]; then
      wget https://dist.apache.org/repos/dist/dev/tomcat/tomcat-9/v${TC_VERSION}/bin/apache-tomcat-${TC_VERSION}.tar.gz
      if [ $? -ne 0 ]; then
        echo "Can't find tomcat: ${TC_VERSION}"
        exit 1
      fi
    fi 
  fi
  tar xvf apache-tomcat-${TC_VERSION}.tar.gz
fi

rm -f apache-tomcat-${TC_VERSION}/bin/setenv.sh
echo "export LD_LIBRARY_PATH=`pwd`/tomcat-native-${VERSION}-src/native/.libs" > apache-tomcat-${TC_VERSION}/bin/setenv.sh
chmod a+x apache-tomcat-${TC_VERSION}/bin/setenv.sh

# Arrange the server.xml to create the connector to test
sed -i '/8080/i \
    \<Connector port="8443" protocol="org.apache.coyote.http11.Http11AprProtocol"\
               maxThreads="150" SSLEnabled="true"\>\
        \<SSLHostConfig\>\
            \<Certificate certificateKeyFile="conf/newkey.pem"\
                         certificateFile="conf/newcert.pem"\
                         type="RSA" /\>\
        \</SSLHostConfig\>\
    \</Connector\>\
\
    <Connector port="8444" protocol="org.apache.coyote.http11.Http11NioProtocol"\
               maxThreads="150" SSLEnabled="true">\
        \<SSLHostConfig\>\
            \<Certificate certificateKeyFile="conf/newkey.pem"\
                         certificateFile="conf/newcert.pem"\
                         type="RSA" /\>\
        \</SSLHostConfig\>\
    \</Connector\>\
' apache-tomcat-${TC_VERSION}/conf/server.xml

# copy the certificates/keys
cp newkey.pem apache-tomcat-${TC_VERSION}/conf/newkey.pem
cp newcert.pem apache-tomcat-${TC_VERSION}/conf/newcert.pem

apache-tomcat-${TC_VERSION}/bin/startup.sh
sleep 10

# check 8080 (tomcat started?)
curl -v  http://localhost:8080/toto
if [ $? -ne 0 ]
then
  echo "curl http://localhost:8080/toto failed"
  exit 1
fi

# check tc-native start message
grep ${VERSION} apache-tomcat-${TC_VERSION}/logs/catalina.out
if [ $? -ne 0 ]
then
  echo "can't ${VERSION} in logs/catalina.out!!!"
  exit 1
fi

# check the apr and nio connectors
curl -v --cacert cacert.pem https://localhost:8443/toto
if [ $? -ne 0 ]
then
  echo "apr connector failed"
  exit 1
fi

curl -v --cacert cacert.pem https://localhost:8444/toto
if [ $? -ne 0 ]
then
  echo "nio connector failed"
  exit 1
fi

# now testing the sources...
rm -rf apache-tomcat-${TC_VERSION}-src
rm -f apache-tomcat-*
wget https://dist.apache.org/repos/dist/dev/tomcat/tomcat-9/v${TC_VERSION}/src/apache-tomcat-${TC_VERSION}-src.tar.gz
if [ $? -ne 0 ]; then
    wget http://mirror.easyname.ch/apache/tomcat/tomcat-9/v${TC_VERSION}/src/apache-tomcat-${TC_VERSION}-src.tar.gz
    if [ $? -ne 0 ]; then
      echo "Can't find tomcat: ${TC_VERSION}"
      exit 1
    fi
fi
tar xvf apache-tomcat-${TC_VERSION}-src.tar.gz
(cd apache-tomcat-${TC_VERSION}-src
ant
if [ $? -ne 0 ]; then
  echo "Build failed"
  exit 1
fi
# copy the .so in bin
cp ../tomcat-native-${VERSION}-src/native/.libs/*.so output/build/bin
# Exclude tests that depend too much on openssl versions.
echo "test.exclude=**/TestCipher.java,**/TestOpenSSLCipherConfigurationParser.java" >> build.properties.default
ant test
if [ $? -ne 0 ]; then
  echo "Test failed"
  exit 1
fi
) || exit 1

echo ""
echo "DONE: All OK"
