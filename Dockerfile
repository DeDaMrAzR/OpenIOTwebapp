ARG NGINX_IMAGE=nginx:alpine
FROM ${NGINX_IMAGE}

COPY nginx.conf /etc/nginx/nginx.conf
COPY startup.js templateParser.js tuyaExporter.js /srv/webapp/
COPY lib/*.js /srv/webapp/lib/
COPY vue/*.vue /srv/webapp/vue/

USER nginx
EXPOSE 8080
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
