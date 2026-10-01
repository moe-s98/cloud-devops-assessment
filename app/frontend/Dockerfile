# Local development only. In AWS the frontend is static files on S3 + CloudFront.
FROM nginxinc/nginx-unprivileged:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html app.js styles.css /usr/share/nginx/html/
EXPOSE 8080
