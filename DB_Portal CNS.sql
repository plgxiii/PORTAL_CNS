CREATE DATABASE IF NOT EXISTS Portal_CNS;
USE Portal_CNS;

-- ==========================================================
-- 1. TABELAS DE APOIO (CADASTROS BASE)
-- ==========================================================

CREATE TABLE IF NOT EXISTS Marca (
    Id_Marca INT PRIMARY KEY AUTO_INCREMENT,
    Nome_Marca VARCHAR(100) NOT NULL,
    Descricao VARCHAR(255) NULL 
);

CREATE TABLE IF NOT EXISTS Categoria (
    Id_Categoria INT PRIMARY KEY AUTO_INCREMENT,
    Nome_Categoria VARCHAR(100) NOT NULL,
    Descricao VARCHAR(255) NULL
);

CREATE TABLE IF NOT EXISTS Setor (
    Id_Setor INT AUTO_INCREMENT PRIMARY KEY,
    Nome_Setor VARCHAR(100) NOT NULL,
    Ativo BOOLEAN DEFAULT 1
);

CREATE TABLE IF NOT EXISTS Igreja (
    Id_Igreja INT AUTO_INCREMENT PRIMARY KEY,
    Nome VARCHAR(150) NOT NULL,
    Ativo BOOLEAN DEFAULT 1
);

-- ==========================================================
-- 2. USUÁRIOS E FORNECEDORES
-- ==========================================================

CREATE TABLE IF NOT EXISTS Usuario (
    Id_Usuario INT PRIMARY KEY AUTO_INCREMENT,
    Nome VARCHAR(150) NOT NULL,
    Email VARCHAR(150) NOT NULL UNIQUE,
    Senha VARCHAR(255) NOT NULL,
    Tipo ENUM('Admin','Gerente','Requisitante') NOT NULL,
    Ativo TINYINT(1) DEFAULT 1,
    Id_Setor INT,
    FOREIGN KEY (Id_Setor) REFERENCES Setor(Id_Setor)
);

CREATE TABLE IF NOT EXISTS Fornecedor (
    Id_Fornecedor INT PRIMARY KEY AUTO_INCREMENT,
    Nome VARCHAR(150) NOT NULL,
    CNPJ VARCHAR(25) NOT NULL UNIQUE,
    Telefone VARCHAR(20) NOT NULL,
    Email VARCHAR(150) NOT NULL,
    Preferencia_contato ENUM('Email', 'Whats', 'Telefone') NOT NULL,
    Endereco VARCHAR(255) NOT NULL,
    Cidade VARCHAR(100) NOT NULL,
    Estado VARCHAR(50) NOT NULL,
    Cep VARCHAR(15) NOT NULL,
    Website VARCHAR(255) NULL
);

-- ==========================================================
-- 3. PRODUTOS E ESTOQUE
-- ==========================================================

CREATE TABLE IF NOT EXISTS Produto (
    Id_Produto INT PRIMARY KEY AUTO_INCREMENT,
    Nome_Produto VARCHAR(100) NOT NULL,
    Descricao VARCHAR(100) NOT NULL,
    Id_Categoria INT NOT NULL,
    Id_Marca INT NOT NULL,
    Estoque_Minimo INT NOT NULL,
    Ativo BOOLEAN DEFAULT TRUE,
    FOREIGN KEY(Id_Categoria) REFERENCES Categoria(Id_Categoria),
    FOREIGN KEY(Id_Marca) REFERENCES Marca(Id_Marca)
);

CREATE TABLE IF NOT EXISTS Estoque_Atual (
    Id_Produto INT PRIMARY KEY,
    Quantidade_Atual DECIMAL(10,2) NOT NULL DEFAULT 0,
    Ultima_Atualizacao DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY(Id_Produto) REFERENCES Produto(Id_Produto)
);

-- ==========================================================
-- 4. PEDIDOS (SISTEMA MESTRE-DETALHE)
-- ==========================================================

CREATE TABLE IF NOT EXISTS Pedido (
    Id_Pedido INT PRIMARY KEY AUTO_INCREMENT,
    Id_Usuario INT NOT NULL,
    Id_Setor INT NOT NULL,
    Data_Pedido DATETIME NOT NULL,
    Status_Pedido VARCHAR(50) DEFAULT 'Pendente',
    Observacao_Adm TEXT NULL,
    INDEX idx_status (Status_Pedido),
    FOREIGN KEY(Id_Usuario) REFERENCES Usuario(Id_Usuario),
    FOREIGN KEY(Id_Setor) REFERENCES Setor(Id_Setor)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Item_Pedido (
    Id_Item INT PRIMARY KEY AUTO_INCREMENT,
    Id_Pedido INT NOT NULL,
    Id_Produto INT NOT NULL,
    Produto_Solicitado VARCHAR(100) NOT NULL,
    Quantidade_Pedido DECIMAL(10,2) NOT NULL,
    Quantidade_Entregue DECIMAL(10,2) DEFAULT 0,
    Observacao_Item TEXT NULL,
    FOREIGN KEY(Id_Pedido) REFERENCES Pedido(Id_Pedido) ON DELETE CASCADE,
    FOREIGN KEY(Id_Produto) REFERENCES Produto(Id_Produto) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ==========================================================
-- 5. MOVIMENTAÇÕES E HISTÓRICO
-- ==========================================================

CREATE TABLE IF NOT EXISTS Movimentacao_Produto (
    Id_Entrada_Produto INT PRIMARY KEY AUTO_INCREMENT,
    Id_Produto INT NOT NULL,
    Quantidade DECIMAL(10,2) NOT NULL,
    Preco_Produto DECIMAL(10,2) NOT NULL,
    Data_Entrada DATETIME NOT NULL,
    Num_Nota_Fiscal INT NOT NULL,
    Lote VARCHAR(50) NOT NULL,
    Data_Validade DATE,
    Id_Fornecedor INT NOT NULL,
    Id_Usuario INT NOT NULL,
    FOREIGN KEY (Id_Produto) REFERENCES Produto(Id_Produto),
    FOREIGN KEY(Id_Fornecedor) REFERENCES Fornecedor(Id_Fornecedor),
    FOREIGN KEY(Id_Usuario) REFERENCES Usuario(Id_Usuario)
);

CREATE TABLE IF NOT EXISTS Saida_Produto (
    Id_Saida INT PRIMARY KEY AUTO_INCREMENT,
    Id_Produto INT NOT NULL,
    Id_Pedido INT NULL,
    Quantidade DECIMAL(10,2) NOT NULL,
    Data_Saida DATETIME NOT NULL,
    Id_Usuario INT NOT NULL,
    Destino_Setor VARCHAR(100) NOT NULL,
    Responsavel_Retirada VARCHAR(100) NOT NULL,
    Motivo ENUM ('Pedido','Avaria','Vencimento','Ajuste') NOT NULL,
    FOREIGN KEY (Id_Produto) REFERENCES Produto(Id_Produto),
    FOREIGN KEY(Id_Usuario) REFERENCES Usuario(Id_Usuario),
    FOREIGN KEY(Id_Pedido) REFERENCES Pedido(Id_Pedido) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS Historico_Relatorios (
    Id_Registro INT PRIMARY KEY AUTO_INCREMENT,
    Id_Local VARCHAR(100) NOT NULL,
    Tipo_Relatorio VARCHAR(50) NOT NULL,
    Periodo_Inicio DATE NULL,
    Periodo_Fim DATE NULL,
    Data_Geracao DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ==========================================================
-- 6. TRIGGERS UNIFICADAS (LÓGICA AUTOMÁTICA)
-- ==========================================================

DELIMITER //

-- Trigger: Atualiza estoque na ENTRADA de nota fiscal
DROP TRIGGER IF EXISTS trg_atualiza_estoque_entrada //
CREATE TRIGGER trg_atualiza_estoque_entrada
AFTER INSERT ON Movimentacao_Produto
FOR EACH ROW
BEGIN
    INSERT INTO Estoque_Atual (Id_Produto, Quantidade_Atual, Ultima_Atualizacao)
    VALUES (NEW.Id_Produto, NEW.Quantidade, NOW())
    ON DUPLICATE KEY UPDATE 
        Quantidade_Atual = Quantidade_Atual + NEW.Quantidade,
        Ultima_Atualizacao = NOW();
END //

-- Trigger: Atualiza estoque em qualquer SAÍDA (Manual ou Automática)
DROP TRIGGER IF EXISTS trg_atualiza_estoque_saida //
CREATE TRIGGER trg_atualiza_estoque_saida
AFTER INSERT ON Saida_Produto
FOR EACH ROW
BEGIN
    UPDATE Estoque_Atual 
    SET Quantidade_Atual = Quantidade_Atual - NEW.Quantidade,
        Ultima_Atualizacao = NOW()
    WHERE Id_Produto = NEW.Id_Produto;
END //

-- Trigger: Quando o Pedido vira 'Finalizado', gera a Saída Automática
DROP TRIGGER IF EXISTS trg_pedido_para_saida //
CREATE TRIGGER trg_pedido_para_saida    
AFTER UPDATE ON Pedido
FOR EACH ROW
BEGIN
    IF NEW.Status_Pedido = 'Finalizado' AND OLD.Status_Pedido <> 'Finalizado' THEN
        INSERT INTO Saida_Produto (
            Id_Produto, 
            Id_Pedido, 
            Quantidade, 
            Data_Saida, 
            Id_Usuario, 
            Destino_Setor, 
            Responsavel_Retirada, 
            Motivo
        )
        SELECT 
            ip.Id_Produto, 
            NEW.Id_Pedido, 
            ip.Quantidade_Entregue, 
            NOW(), 
            NEW.Id_Usuario, 
            s.Nome_Setor, 
            'Sistema - Baixa Automática', 
            'Pedido'
        FROM Item_Pedido ip
        INNER JOIN Setor s ON s.Id_Setor = NEW.Id_Setor
        WHERE ip.Id_Pedido = NEW.Id_Pedido AND ip.Quantidade_Entregue > 0;
    END IF;
END //

DELIMITER ;

-- ==========================================================
-- 7. CARGA INICIAL
-- ==========================================================

INSERT IGNORE INTO Usuario (Nome, Email, Senha, Tipo) 
VALUES ('Admin', 'adm@gmail.com', '123', 'Admin');