<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Fase 1:
 * - transactions.balance_applied: a transação só entra no saldo quando a data chega.
 * - recurring_transactions.anchor_date: data da 1ª ocorrência, base para calcular as próximas
 *   sem "escorregar" o dia (31/01 → 28/02 → 31/03, e não 28/03).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->boolean('balance_applied')->default(false)->after('date');
        });

        Schema::table('recurring_transactions', function (Blueprint $table) {
            $table->date('anchor_date')->nullable()->after('frequency');
        });

        $today = now()->toDateString();

        DB::transaction(function () use ($today) {
            // Regra antiga: transações simples/recorrentes e a 1ª parcela já tinham entrado no saldo.
            DB::table('transactions')
                ->where(fn ($q) => $q->whereNull('installment_number')->orWhere('installment_number', 1))
                ->update(['balance_applied' => true]);

            // Regra nova: o que tem data futura sai do saldo até a data chegar.
            $future = DB::table('transactions')
                ->where('balance_applied', true)
                ->where('date', '>', $today)
                ->get(['id', 'account_id', 'type', 'amount']);

            foreach ($future as $t) {
                $delta = $t->type === 'income' ? -(float) $t->amount : (float) $t->amount;

                DB::table('accounts')->where('id', $t->account_id)->increment('balance', $delta);
                DB::table('transactions')->where('id', $t->id)->update(['balance_applied' => false]);
            }

            // Âncora = data da primeira ocorrência já gerada (ou o próximo lançamento).
            foreach (DB::table('recurring_transactions')->get(['id', 'next_run']) as $r) {
                $first = DB::table('transactions')->where('recurring_id', $r->id)->min('date');

                DB::table('recurring_transactions')
                    ->where('id', $r->id)
                    ->update(['anchor_date' => $first ?? $r->next_run]);
            }
        });
    }

    public function down(): void
    {
        Schema::table('recurring_transactions', function (Blueprint $table) {
            $table->dropColumn('anchor_date');
        });

        Schema::table('transactions', function (Blueprint $table) {
            $table->dropColumn('balance_applied');
        });
    }
};
