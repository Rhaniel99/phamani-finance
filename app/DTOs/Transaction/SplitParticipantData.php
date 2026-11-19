<?php

namespace App\DTOs\Transaction;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Data;

/**
 * Um participante da divisão. contact_id null = você.
 * amount só é usado no modo "valores" (custom).
 */
class SplitParticipantData extends Data
{
    public function __construct(
        public ?string $contact_id = null,
        public ?float $amount = null,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'contact_id' => ['nullable', 'uuid', Rule::exists('contacts', 'id')->where('user_id', Auth::id())],
            'amount' => ['nullable', 'numeric', 'min:0'],
        ];
    }
}
