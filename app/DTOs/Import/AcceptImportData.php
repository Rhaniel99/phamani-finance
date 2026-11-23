<?php

namespace App\DTOs\Import;

use Spatie\LaravelData\Attributes\DataCollectionOf;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Data;

/**
 * Revisão concluída: o que lançar, o que já estava cadastrado (marca como conferido) e em qual fatura.
 */
class AcceptImportData extends Data
{
    public function __construct(
        /** Mês de referência da fatura (Y-m-d, dia 1). */
        #[Date]
        public string $reference,

        /** @var array<int, AcceptImportLineData> */
        #[DataCollectionOf(AcceptImportLineData::class)]
        public array $lines = [],

        /** Transações já cadastradas que bateram com o extrato. @var list<string> */
        public array $reconcile = [],

        /** Lembrar nome/categoria/tags de cada loja para a próxima importação. */
        public bool $remember = true,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'lines' => ['array', 'max:300'],
            'reconcile' => ['array', 'max:300'],
            'reconcile.*' => ['uuid'],
        ];
    }
}
