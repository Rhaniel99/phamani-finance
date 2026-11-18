<?php

namespace App\DTOs\Account;

use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Data;

class StoreAccountData extends Data
{
    public function __construct(
        #[Max(100)]
        public string $name,

        #[In(['cash', 'checking', 'savings', 'credit'])]
        public string $type,
    ) {}
}
