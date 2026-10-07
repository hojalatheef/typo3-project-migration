<?php
return [
    'BE' => ['installToolPassword' => '$argon2i$fixture'],
    'DB' => ['Connections' => ['Default' => ['driver' => 'mysqli', 'dbname' => 'db', 'host' => 'db', 'user' => 'db', 'password' => 'db']]],
    'FE' => ['additionalAbsRefPrefixDirectories' => 'assets/'],
    'SYS' => ['sitename' => 'ACME Corporate'],
];
