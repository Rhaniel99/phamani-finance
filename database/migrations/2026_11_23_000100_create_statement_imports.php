<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Importação do extrato do cartão (OCR) e a "memória" de lojas.
 *
 * - statement_imports: um upload. status queued → processing → ready (revisão) → done; ou failed.
 *   progress/stage: o que a tela mostra enquanto o OCR roda. result: linhas e seções lidas (JSON).
 *   Os arquivos enviados são apagados assim que o OCR termina.
 * - merchant_rules: "DROGARIA SOFIA" → nome, categoria e tags que você escolheu da última vez.
 *   key "brand:ifood" vale para todas as lojas da marca.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('statement_imports', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('account_id')->constrained('accounts')->cascadeOnDelete();
            $table->string('bank', 20)->default('bradesco');
            $table->string('status', 20)->default('queued');
            $table->unsignedTinyInteger('progress')->default(0);
            $table->string('stage')->nullable();
            $table->text('error')->nullable();
            $table->date('statement_date')->nullable();
            $table->json('files')->nullable();
            $table->json('result')->nullable();
            $table->unsignedSmallInteger('created_count')->default(0);
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'created_at']);
        });

        Schema::create('merchant_rules', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('key');
            $table->string('name');
            $table->foreignUuid('category_id')->nullable()->constrained('categories')->nullOnDelete();
            $table->json('tags')->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('merchant_rules');
        Schema::dropIfExists('statement_imports');
    }
};
