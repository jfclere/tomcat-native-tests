#VERSION=/opt/rh/jws5/root/usr/lib64
VERSION=1.2.31
TC_VERSION=10.1.0-M10
TC_MAJOR=10
#TC_VERSION=9.0.56
#TC_MAJOR=9
#TC_VERSION=8.5.70
#TC_MAJOR=8

# ant for rhel9
ANT_HOME=/home/jfclere/apache-ant-1.10.11

# for panama
PATH=/home/jfclere/JAVA/openjdk-17-panama+3-167_linux-x64_bin/jdk-17/bin:$PATH

# for adoptium
#PATH=/home/jfclere/TMP/jdk8u302-b08/bin:$PATH
#PATH=/home/jfclere/TMP/jdk-11.0.12+7/bin:$PATH
# for openjdk8
#PATH=/usr/lib/jvm/java-1.8.0/bin:$PATH
# find java_home (looking for alternatives)
# 2022/01/20  openjdk version "11.0.13" 2021-10-19
JAVA=`which java`
JAVA=`ls -l ${JAVA} | awk '{ print $11 }'`
echo $JAVA | grep alternatives
if [ $? -eq 0 ]; then
  # We have alternatives let's follow
  if [ ! -z ${JAVA} ]; then
    JAVA=`ls -l ${JAVA} | awk '{ print $11 }'`
  fi
  echo "${JAVA}" | grep jre
  if [ $? -eq 0 ]; then
    JAVA_HOME=`echo "${JAVA}" | sed 's:jre: :' | awk ' { print $1 } '`
  else
    JAVA_HOME=`echo "${JAVA}" | sed 's:/bin/: :' | awk ' { print $1 } '`
  fi
else
  # we have a probably a PATH for example /home/jfclere/TMP/jdk8u292-b10/bin
  JAVA=`which java`
  JAVA_HOME=`echo "${JAVA}" | sed 's:/bin/: :' | awk ' { print $1 } '`
fi
echo "Using: JAVA_HOME ${JAVA_HOME}"

# check for panama
USE_PANAMA=false
java -version 2>&1 | grep panama
if [ $? -eq 0 ]; then
  # don't build tomcat-native
  VERSION=/panama
  USE_PANAMA=true
fi

if $USE_PANAMA; then
  echo "Using PANAMA!"
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

# build tomcat-native is required.
function buildnative
{
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
}

case $VERSION in
  1.2.*)
    buildnative || exit 1
    ;;
  main)
    echo "building ${VERSION} not supported"
    exit 1
    ;;
  /*)
    echo "Using already build tc-native from ${VERSION}"
    ;;
  *)
    echo "building ${VERSION} not supported"
    exit 1
    ;;
esac
  
if [ ! -d apache-tomcat-${TC_VERSION} ]
then
  if [ ! -f apache-tomcat-${TC_VERSION}.tar.gz ]
  then
    wget http://mirror.easyname.ch/apache/tomcat/tomcat-${TC_MAJOR}/v${TC_VERSION}/bin/apache-tomcat-${TC_VERSION}.tar.gz
    if [ $? -ne 0 ]; then
      wget https://dist.apache.org/repos/dist/dev/tomcat/tomcat-${TC_MAJOR}/v${TC_VERSION}/bin/apache-tomcat-${TC_VERSION}.tar.gz
      if [ $? -ne 0 ]; then
        # new location in the cloud...
        # https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.0-M8/bin/apache-tomcat-10.1.0-M8.tar.gz
        echo "trying: https://dlcdn.apache.org/tomcat/tomcat-${TC_MAJOR}/v${TC_VERSION}/bin/apache-tomcat-${TC_VERSION}.tar.gz"
        wget https://dlcdn.apache.org/tomcat/tomcat-${TC_MAJOR}/v${TC_VERSION}/bin/apache-tomcat-${TC_VERSION}.tar.gz
        if [ $? -ne 0 ]; then
          echo "Can't find tomcat: ${TC_VERSION}"
          exit 1
        fi
      fi
    fi 
  fi
  tar xvf apache-tomcat-${TC_VERSION}.tar.gz
fi

# now building panama
if $USE_PANAMA; then
  if [ -d $tomcat-${TC_VERSION} ]; then
    wget https://github.com/apache/tomcat/archive/refs/tags/${TC_VERSION}.tar.gz
    tar xvf ${TC_VERSION}.tar.gz
  fi
  cd tomcat-${TC_VERSION}/modules/openssl-java17
  #jextract @openssl-tomcat.conf openssl.h
  #if [ $? -ne 0 ]; then
  #  echo "pnanama: jextract failed"
  #  exit 1
  #fi
  export JAVA_HOME
  mvn install
  if [ $? -ne 0 ]; then
    echo "pnanama: mvn install failed"
    exit 1
  fi
  # tomcat-coyote-openssl-java17-0.1-SNAPSHOT.jar
  OPENSSL_JAR=`ls target/tomcat-coyote-openssl-java17*`
  echo "panama: openssl jar: $OPENSSL_JAR"
  cd ../../..
fi

rm -f apache-tomcat-${TC_VERSION}/bin/setenv.sh
case $VERSION in
  1.2.*)
    echo "export LD_LIBRARY_PATH=`pwd`/tomcat-native-${VERSION}-src/native/.libs" > apache-tomcat-${TC_VERSION}/bin/setenv.sh
    ;;
  /panama)
    echo "Using openssl-java17 / panama"
    echo "export JAVA_OPTS=\"--enable-native-access=ALL-UNNAMED --add-modules jdk.incubator.foreign\"" > apache-tomcat-${TC_VERSION}/bin/setenv.sh
    cp tomcat-${TC_VERSION}/modules/openssl-java17/${OPENSSL_JAR} apache-tomcat-${TC_VERSION}/lib
    ;;
  *)
    echo "export LD_LIBRARY_PATH=$VERSION" > apache-tomcat-${TC_VERSION}/bin/setenv.sh
    ;;
esac
chmod a+x apache-tomcat-${TC_VERSION}/bin/setenv.sh

# Arrange the server.xml to create the connector to test
if [ $TC_MAJOR != 10 ]; then
  echo "Tomcat 9 or 8"
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
else
  echo "Tomcat 10.1"
  if ${USE_PANAMA}; then
    sed -i '/8080/i \
    <Connector port="8444" protocol="HTTP/1.1"\
               SSLEnabled="true" scheme="https" secure="true"\
               socket.directBuffer="true" socket.directSslBuffer="true"\
               sslImplementationName="org.apache.tomcat.util.net.openssl.panama.OpenSSLImplementation">\
        \<SSLHostConfig certificateVerification="none"\>\
            \<Certificate certificateKeyFile="conf/newkey.pem"\
                         certificateFile="conf/newcert.pem"\
                         type="RSA" /\>\
        \</SSLHostConfig\>\
        \<UpgradeProtocol className="org.apache.coyote.http2.Http2Protocol" \/>\
    \</Connector\>\
'   apache-tomcat-${TC_VERSION}/conf/server.xml
  else
    sed -i '/8080/i \
    <Connector port="8444" protocol="org.apache.coyote.http11.Http11NioProtocol"\
               maxThreads="150" SSLEnabled="true">\
        \<SSLHostConfig\>\
            \<Certificate certificateKeyFile="conf/newkey.pem"\
                         certificateFile="conf/newcert.pem"\
                         type="RSA" /\>\
        \</SSLHostConfig\>\
    \</Connector\>\
'   apache-tomcat-${TC_VERSION}/conf/server.xml
  fi
fi

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
case $VERSION in
  1.2.*)
    STRINGVERSION=$VERSION
    ;;
  /panama)
    echo "Using openssl-java17 / panama"
    STRINGVERSION="panama"
    ;;
  *)
    STRINGVERSION="1.2."
    ;;
esac
grep ${STRINGVERSION} apache-tomcat-${TC_VERSION}/logs/catalina.out
if [ $? -ne 0 ]
then
  echo "can't ${STRINGVERSION} in logs/catalina.out!!!"
  exit 1
fi

# check the apr and nio connectors
if [ $TC_MAJOR != 10 ]; then
  curl -v --cacert cacert.pem https://localhost:8443/toto
  if [ $? -ne 0 ]
  then
    if [ $TC_MAJOR != 10 ]; then
      echo "apr connector failed"
      exit 1
    fi
  fi
fi

curl -v --cacert cacert.pem https://localhost:8444/toto
if [ $? -ne 0 ]
then
  echo "nio connector failed"
  exit 1
fi

# now testing the sources...
rm -rf apache-tomcat-${TC_VERSION}-src
wget https://dist.apache.org/repos/dist/dev/tomcat/tomcat-${TC_MAJOR}/v${TC_VERSION}/src/apache-tomcat-${TC_VERSION}-src.tar.gz
if [ $? -ne 0 ]; then
    wget http://mirror.easyname.ch/apache/tomcat/tomcat-${TC_MAJOR}/v${TC_VERSION}/src/apache-tomcat-${TC_VERSION}-src.tar.gz
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
case $VERSION in
  1.2.*)
    cp ../tomcat-native-${VERSION}-src/native/.libs/*.so output/build/bin
    mkdir output/build/bin/native
    cp ../tomcat-native-${VERSION}-src/native/.libs/*.so output/build/bin/native
    ;;
  /panama)
    echo "Using openssl-java17 / panama"
    mkdir -p $HOME/tomcat-build-libs/tomcat-coyote-openssl-java17-0.1
    cp tomcat-${TC_VERSION}/modules/openssl-java17/${OPENSSL_JAR} $HOME/tomcat-build-libs/tomcat-coyote-openssl-java17-0.1/tomcat-coyote-openssl-java17-0.1.jar
    ;;
  *)
    cp ${VERSION}/*.so output/build/bin
    mkdir output/build/bin/native
    cp ${VERSION}/*.so output/build/bin/native
    ;;
esac
# Exclude tests that depend too much on openssl versions.
echo "test.exclude=**/TestCipher.java,**/TestOpenSSLCipherConfigurationParser.java" >> build.properties.default
${ANT_HOME}/bin/ant test
if [ $? -ne 0 ]; then
  echo "Test failed"
  exit 1
fi
) || exit 1

echo ""
echo "DONE: All OK"
