<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Compras no cartão: o status passa a seguir a fatura ("Na fatura" até a fatura ser paga),
 * em vez de nascerem pagas. As cópias compartilhadas seguem a original.
 * E reconciled_at: "conferido" na lista da fatura.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->timestamp('reconciled_at')->nullable();
        });

        $credit = DB::table('accounts')->select('id')->where('type', 'credit');

        DB::table('transactions')
            ->whereIn('account_id', $credit)
            ->update([
                'paid_at' => DB::raw('(select i.paid_at from credit_card_invoices i where i.id = transactions.invoice_id)'),
            ]);

        // Cópias de compras no cartão: mesmo status da original.
        $cardSources = DB::table('transactions')->whereIn('account_id', $credit)->get(['id', 'paid_at']);

        foreach ($cardSources as $source) {
            DB::table('transactions')->where('mirrored_from_id', $source->id)->update(['paid_at' => $source->paid_at]);
        }
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropColumn('reconciled_at');
        });
    }
};
