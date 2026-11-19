<?php

namespace App\DTOs\Account;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
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

        // Só para cartão de crédito
        public ?float $credit_limit = null,
        public ?int $closing_day = null,
        public ?int $due_day = null,
        public ?string $payment_account_id = null,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'credit_limit' => ['nullable', 'required_if:type,credit', 'numeric', 'min:0'],
            'closing_day' => ['nullable', 'required_if:type,credit', 'integer', 'between:1,31'],
            'due_day' => ['nullable', 'required_if:type,credit', 'integer', 'between:1,31'],
            'payment_account_id' => [
                'nullable', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id())->whereNot('type', 'credit'),
            ],
        ];
    }
}
