TOMCAT_VERSION=10.1.18
TCK_VERSION=6.0.1
SERVLET_TCK_HOME=`pwd`/$$
TOMCAT_HOME=`pwd`/apache-tomcat-$TOMCAT_VERSION
if [ ! -d $TOMCAT_HOME ]; then
  echo "No tomcat install to test"
fi
if [ ! -d $TOMCAT_HOME/modules ]; then
  mkdir $TOMCAT_HOME/modules
  cp $TOMCAT_HOME/lib/servlet-api.jar $TOMCAT_HOME/modules
  cp $TOMCAT_HOME/lib/annotations-api.jar $TOMCAT_HOME/modules
fi

# stop the tomcat
ps -ef | grep java | grep $TOMCAT_VERSION
if [ $? -eq 0 ]; then
 (cd $TOMCAT_HOME; bin/shutdown.sh)
fi

mkdir $SERVLET_TCK_HOME
if [ ! -f servlet-tck-$TCK_VERSION.zip ]; then
  #wget https://download.eclipse.org/ee4j/jakartaee-tck/jakartaee10/promoted/epl/servlet-tck-$TCK_VERSION.zip
  wget https://download.eclipse.org/jakartaee/servlet/6.0/jakarta-servlet-tck-$TCK_VERSION.zip
fi
(cd $SERVLET_TCK_HOME; unzip ../jakarta-servlet-tck-$TCK_VERSION.zip)
if [ ! -f cacerts.jks ]; then
  keytool -import -alias cts -file $SERVLET_TCK_HOME/servlet-tck/bin/certificates/cts_cert -storetype JKS -keystore cacerts.jks -storepass changeit -noprompt
fi
cp cacerts.jks $TOMCAT_HOME/conf
cp $SERVLET_TCK_HOME/servlet-tck/bin/certificates/clientcert.jks $TOMCAT_HOME/conf
sed -i "s:web.home=:web.home=$TOMCAT_HOME:" $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte
sed -i 's:jakarta.servlet-api:servlet-api:' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte
sed -i 's:jakarta.annotation-api:annotation-api:' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte
sed -i 's:webServerHost=:webServerHost=localhost:' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte
sed -i 's:webServerPort=:webServerPort=8080:' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte
sed -i 's:securedWebServicePort=:securedWebServicePort=8443:' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte
sed -i 's:domains/domain1/config:conf:' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte

echo "$SERVLET_TCK_HOME/servlet-tck/bin/ts.jte configured"

# not sure it is usefull...
#sed -i '/-Dbytecheck=true/a-Djava.endorsed.dirs=${ts.home}\/endorsedlib \\' $SERVLET_TCK_HOME/servlet-tck/bin/ts.jte

(cd $SERVLET_TCK_HOME; find . -name *.war -exec cp {} $TOMCAT_HOME/webapps/ \;)

if [ ! -f $TOMCAT_HOME/bin/setenv.sh ]; then
  touch $TOMCAT_HOME/bin/setenv.sh
  chmod +x $TOMCAT_HOME/bin/setenv.sh
fi
grep JAVA_OPTS $TOMCAT_HOME/bin/setenv.sh
if [ $? -ne 0 ]; then
  echo "export JAVA_OPTS=\"-Dorg.apache.catalina.STRICT_SERVLET_COMPLIANCE=true -Dorg.apache.tomcat.util.http.ServerCookie.FWD_SLASH_IS_SEPARATOR=false -Duser.language=en -Duser.country=US\"" >> $TOMCAT_HOME/bin/setenv.sh
fi
grep crossContex $TOMCAT_HOME/conf/context.xml
if [ $? -ne 0 ]; then
  sed -i 's:<Context>:<Context crossContext="true" resourceOnlyServlets="jsp">:' $TOMCAT_HOME/conf/context.xml
  # not sure it is usefull...
  # sed -i '/crossContext/a<CookieProcessor className="org.apache.tomcat.util.http.LegacyCookieProcessor" alwaysAddExpires="true" forwardSlashIsSeparator="false" />' $TOMCAT_HOME/conf/context.xml
fi
grep Burlington $TOMCAT_HOME/conf/tomcat-users.xml
if [ $? -ne 0 ]; then
  sed -i '/<\/tomcat-users>/d' $TOMCAT_HOME/conf/tomcat-users.xml
  cat <<EOF >> $TOMCAT_HOME/conf/tomcat-users.xml
<user username="CN=CTS, OU=Java Software, O=Sun Microsystems Inc., L=Burlington, ST=MA, C=US" roles="Administrator"/>
<user username="j2ee" password="j2ee" roles="Administrator,Employee" />
<user username="javajoe" password="javajoe" roles="VP,Manager" />
</tomcat-users>
EOF
fi
grep request-character-encoding $TOMCAT_HOME/conf/web.xml
if [ $? -eq 0 ]; then
  sed -i '/request-character-encoding/a \
  <locale-encoding-mapping-list> \
    <locale-encoding-mapping> \
      <locale>ja<\/locale> \
      <encoding>Shift_JIS<\/encoding> \
    <\/locale-encoding-mapping> \
  <\/locale-encoding-mapping-list> ' $TOMCAT_HOME/conf/web.xml
  sed -i '/request-character-encoding/d' $TOMCAT_HOME/conf/web.xml
  sed -i '/response-character-encoding/d' $TOMCAT_HOME/conf/web.xml
fi
grep myTrailer $TOMCAT_HOME/conf/server.xml
if [ $? -ne 0 ]; then
  # remove it
  sed -i 's:<Connector port="8080":<Connector port="66666":' $TOMCAT_HOME/conf/server.xml
  # Add the one we need.
  sed -i '/Service name/a \
  <Connector port="8080" protocol="HTTP\/1.1" \
             allowedTrailerHeaders="myTrailer, myTrailer2" \
             connectionTimeout="20000" \
             redirectPort="8443" \
             maxParameterCount="1000">  \
     <UpgradeProtocol className="org.apache.coyote.http2.Http2Protocol" \/> \
  <\/Connector>' $TOMCAT_HOME/conf/server.xml
fi
grep "clientcert.jks" $TOMCAT_HOME/conf/server.xml
if [ $? -ne 0 ]; then
  # Add the one we need.
  sed -i '/Service name/a \
  <Connector port="8443" protocol="HTTP\/1.1" SSLEnabled="true"> \
    <SSLHostConfig truststoreFile="conf/cacerts.jks"> \
        <Certificate certificateKeystoreFile="conf/clientcert.jks" \
                     certificateKeystorePassword="changeit" \
                     type="RSA" \/> \
    <\/SSLHostConfig> \
  <\/Connector>' $TOMCAT_HOME/conf/server.xml

fi

(cd $TOMCAT_HOME; bin/startup.sh)
