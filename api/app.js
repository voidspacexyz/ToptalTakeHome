var express = require('express');
var app = express();
var uuid = require('node-uuid');

var pg = require('pg');
const conString = {
    user: process.env.DBUSER,
    database: process.env.DB,
    password: process.env.DBPASS,
    host: process.env.DBHOST,
    port: process.env.DBPORT,
    ssl: { rejectUnauthorized: false }  // Azure PostgreSQL Flexible Server requires SSL
};

// Shared pool — created once at startup, reused across requests
// Delete PGSSLMODE env var so it cannot override the explicit ssl: config above.
// Azure PostgreSQL Flexible Server mandates SSL; pg respects libpq env vars which
// can silently disable encryption if set in the container environment.
delete process.env.PGSSLMODE;
const pool = new pg.Pool(conString);

// Routes
app.get('/api/status', function(req, res) {
  pool.connect((err, client, release) => {
    if (err) {
      console.error('Error acquiring client', err.stack);
      return res.status(503).json({ error: 'Database connection failed', message: err.message });
    }
    client.query('SELECT now() as time', (err, result) => {
      release();
      if (err) {
        console.error('Error executing query', err.stack);
        return res.status(503).json({ error: 'Query failed', message: err.message });
      }
      res.status(200).json(result.rows);
    });
  });
});

// catch 404 and forward to error handler
app.use(function(req, res, next) {
  var err = new Error('Not Found');
  err.status = 404;
  next(err);
});

// error handlers

// development error handler
// will print stacktrace
if (app.get('env') === 'development') {
  app.use(function(err, req, res, next) {
    res.status(err.status || 500);
    res.json({
      message: err.message,
      error: err
    });
  });
}

// production error handler
// no stacktraces leaked to user
app.use(function(err, req, res, next) {
  res.status(err.status || 500);
  res.json({
    message: err.message,
    error: {}
  });
});


module.exports = app;
