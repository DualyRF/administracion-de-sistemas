rm /var/lib/tomcat/webapps/ROOT/index.jsp
chmod 644 /var/lib/tomcat/webapps/ROOT/index.html
systemctl restart tomcat
curl -I http://localhost:8888