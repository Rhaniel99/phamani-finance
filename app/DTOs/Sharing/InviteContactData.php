<?php

namespace App\DTOs\Sharing;

use Spatie\LaravelData\Attributes\Validation\Email;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Data;

class InviteContactData extends Data
{
    public function __construct(
        /** E-mail do Google da pessoa. */
        #[Email, Max(255)]
        public string $email,
    ) {}
}
