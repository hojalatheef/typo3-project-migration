<?php
namespace Acme\Sitepackage\UserFunc;

final class Copyright
{
    public function render(string $content, array $conf): string
    {
        return '© ' . date('Y') . ' ACME';
    }
}
