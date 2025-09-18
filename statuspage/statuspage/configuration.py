#
# Required Settings
#
import os
from urllib.parse import urlparse
import dj_database_url



# This is a list of valid fully-qualified domain names (FQDNs) for the Status-Page server. Status-Page will not permit
# write access to the server via any other hostnames. The first FQDN in the list will be treated as the preferred name.
#
# Example: ALLOWED_HOSTS = ['status-page.example.com', 'status-page.internal.local']
STATUS_HOSTNAME = os.environ.get("STATUS_HOSTNAME")
if STATUS_HOSTNAME:
    ALLOWED_HOSTS = [STATUS_HOSTNAME]
    PROTOCOL = os.environ.get("SITE_PROTOCOL", "http")
    SITE_URL = f"{PROTOCOL}://{STATUS_HOSTNAME}"
else:
    ALLOWED_HOSTS = ["*"]
    SITE_URL = "http://status-page-ay.com"
    
# PostgreSQL database configuration. See the Django documentation for a complete list of available parameters:
#   https://docs.djangoproject.com/en/stable/ref/settings/#databases


DATABASE_URL = os.environ.get("DATABASE_URL")
if DATABASE_URL:
    # Use dj-database-url to safely parse full URL into Django settings
    DATABASE = dj_database_url.parse(
        DATABASE_URL,
        conn_max_age=300,  # same as your old CONN_MAX_AGE
        ssl_require=True   # enforces ?sslmode=require handling
    )
else:
    # Fallback for local/dev
    DATABASE = {
        'NAME': 'statuspage',
        'USER': 'statuspage',
        'PASSWORD': 'status',
        'HOST': 'localhost',
        'PORT': '5432',
        'CONN_MAX_AGE': 300,
    }


# Redis database settings. Redis is used for caching and for queuing background tasks. A separate configuration exists
# for each. Full connection details are required.

REDIS_URL = os.environ.get("REDIS_URL")
if REDIS_URL:
    r = urlparse(REDIS_URL)
    host = r.hostname or 'localhost'
    port = r.port or 6379
    # We use DB 0 for tasks and DB 1 for caching to mirror your original structure
    REDIS = {
        'tasks':   {'HOST': host, 'PORT': port, 'DATABASE': 0, 'SSL': (r.scheme == 'rediss')},
        'caching': {'HOST': host, 'PORT': port, 'DATABASE': 1, 'SSL': (r.scheme == 'rediss')},
    }
else:
    # Fallback for local/dev
    REDIS = {
        'tasks': {
            'HOST': 'localhost',
            'PORT': 6379,
            'DATABASE': 0,
            'SSL': False,
        },
        'caching': {
            'HOST': 'localhost',
            'PORT': 6379,
            'DATABASE': 1,
            'SSL': False,
        }
    }


# This key is used for secure generation of random numbers and strings. It must never be exposed outside of this file.
# For optimal security, SECRET_KEY should be at least 50 characters in length and contain a mix of letters, numbers, and
# symbols. Status-Page will not run without this defined. For more information, see
# https://docs.djangoproject.com/en/stable/ref/settings/#std:setting-SECRET_KEY
SECRET_KEY = os.environ.get(
    "SECRET_KEY",
    "abQ7skRUStqCH_tLvtV_d8Z3Y4d2Jp7jFem2IOla-UJSZQtNqssTjYVv9TAcE1on"  # dev/local only
)

#SECRET_KEY = 'ZcyS%a_0^PAwPk4ZC5g@SUp-Y&Jhb^ER+_SL*q-glehDZmS$OZ'

#
# Optional Settings
#

# Specify one or more name and email address tuples representing Status-Page administrators. These people will be notified of
# application errors (assuming correct email settings are provided).
ADMINS = [
    # ('John Doe', 'jdoe@example.com'),
]

# Enable any desired validators for local account passwords below. For a list of included validators, please see the
# Django documentation at https://docs.djangoproject.com/en/stable/topics/auth/passwords/#password-validation.
AUTH_PASSWORD_VALIDATORS = [
    # {
    #     'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    #     'OPTIONS': {
    #         'min_length': 10,
    #     }
    # },
]

# Base URL path if accessing Status-Page within a directory. For example, if installed at
# https://example.com/status-page/, set: BASE_PATH = 'status-page/'
BASE_PATH = ''

# API Cross-Origin Resource Sharing (CORS) settings. If CORS_ORIGIN_ALLOW_ALL is set to True, all origins will be
# allowed. Otherwise, define a list of allowed origins using either CORS_ORIGIN_WHITELIST or
# CORS_ORIGIN_REGEX_WHITELIST. For more information, see https://github.com/ottoyiu/django-cors-headers
CORS_ORIGIN_ALLOW_ALL = False
CORS_ORIGIN_WHITELIST = [
    # 'https://hostname.example.com',
]
CORS_ORIGIN_REGEX_WHITELIST = [
    # r'^(https?://)?(\w+\.)?example\.com$',
]

# Set to True to enable server debugging. WARNING: Debugging introduces a substantial performance penalty and may reveal
# sensitive information about your installation. Only enable debugging while performing testing. Never enable debugging
# on a production system.
DEBUG = False

# Email settings
EMAIL = {
    'SERVER': 'localhost',
    'PORT': 25,
    'USERNAME': '',
    'PASSWORD': '',
    'USE_SSL': False,
    'USE_TLS': False,
    'TIMEOUT': 10,  # seconds
    'FROM_EMAIL': '',
}

# IP addresses recognized as internal to the system. The debugging toolbar will be available only to clients accessing
# Status-Page from an internal IP.
INTERNAL_IPS = ('127.0.0.1', '::1')

# Enable custom logging. Please see the Django documentation for detailed guidance on configuring custom logs:
#   https://docs.djangoproject.com/en/stable/topics/logging/
LOGGING = {}

# The length of time (in seconds) for which a user will remain logged into the web UI before being prompted to
# re-authenticate. (Default: 1209600 [14 days])
LOGIN_TIMEOUT = None

# The file path where uploaded media such as image attachments are stored. A trailing slash is not needed. Note that
# the default value of this setting is derived from the installed location.
# MEDIA_ROOT = '/opt/status-page/statuspage/media'

# Overwrite Field Choices for specific Models (Note that this may break functionality!
# Please check the docs, before overwriting any choices.
FIELD_CHOICES = {}

PLUGINS = [
    # 'sp_uptimerobot',  # Built-In Plugin for UptimeRobot integration
    # 'sp_external_status_providers',  # Built-In Plugin for integrating external Status Pages
]

# Plugins configuration settings. These settings are used by various plugins that the user may have installed.
# Each key in the dictionary is the name of an installed plugin and its value is a dictionary of settings.
PLUGINS_CONFIG = {
    'sp_uptimerobot': {
        'uptime_robot_api_key': '',
    },
}

# Maximum execution time for background tasks, in seconds.
RQ_DEFAULT_TIMEOUT = 300

# The name to use for the csrf token cookie.
CSRF_COOKIE_NAME = 'csrftoken'

# The name to use for the session cookie.
SESSION_COOKIE_NAME = 'sessionid'

# Time zone (default: UTC)
TIME_ZONE = 'UTC'

# Date/time formatting. See the following link for supported formats:
# https://docs.djangoproject.com/en/stable/ref/templates/builtins/#date
DATE_FORMAT = 'N j, Y'
SHORT_DATE_FORMAT = 'Y-m-d'
TIME_FORMAT = 'g:i a'
SHORT_TIME_FORMAT = 'H:i:s'
DATETIME_FORMAT = 'N j, Y g:i a'
SHORT_DATETIME_FORMAT = 'Y-m-d H:i'

# Static files (CSS, JavaScript, Images)
STATIC_URL = "/static/"
STATIC_ROOT = os.path.join(os.path.dirname(__file__), "static")

# Media files (uploads)
MEDIA_URL = "/media/"
MEDIA_ROOT = os.path.join(os.path.dirname(__file__), "media")
