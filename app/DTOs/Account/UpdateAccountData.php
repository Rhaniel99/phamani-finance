<?php

namespace App\DTOs\Account;

use App\Models\Account;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Data;

/**
 * Edição de conta. O tipo não muda; os campos de cartão só valem (e são obrigatórios) para cartão.
 */
class UpdateAccountData extends Data
{
    public function __construct(
        #[Max(100)]
        public string $name,

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
        $account = request()->route('account');
        $required = $account instanceof Account && $account->isCreditCard() ? 'required' : 'nullable';

        return [
            'credit_limit' => [$required, 'numeric', 'min:0'],
            'closing_day' => [$required, 'integer', 'between:1,31'],
            'due_day' => [$required, 'integer', 'between:1,31'],
            'payment_account_id' => [
                'nullable', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id())->whereNot('type', 'credit'),
            ],
        ];
    }
}
